#include "vt.h"

#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(FOOT_GRAPHEME_CLUSTERING)
 #include <utf8proc.h>
#endif

#define LOG_MODULE "vt"
#define LOG_ENABLE_DBG 0
#include "log.h"
#include "char32.h"
#include "config.h"
#include "csi.h"
#include "dcs.h"
#include "debug.h"
#include "osc.h"
#include "sixel.h"
#include "util.h"
#include "xmalloc.h"

#define UNHANDLED() LOG_DBG("unhandled: %s", esc_as_string(term, final))

/* https://vt100.net/emu/dec_ansi_parser */

enum state {
    STATE_GROUND,
    STATE_ESCAPE,
    STATE_ESCAPE_INTERMEDIATE,

    STATE_CSI_ENTRY,
    STATE_CSI_PARAM,
    STATE_CSI_INTERMEDIATE,
    STATE_CSI_IGNORE,

    STATE_OSC_STRING,

    STATE_DCS_ENTRY,
    STATE_DCS_PARAM,
    STATE_DCS_INTERMEDIATE,
    STATE_DCS_IGNORE,
    STATE_DCS_PASSTHROUGH,

    STATE_SOS_PM_APC_STRING,

    STATE_UTF8_21,
    STATE_UTF8_31,
    STATE_UTF8_32,
    STATE_UTF8_41,
    STATE_UTF8_42,
    STATE_UTF8_43,
};

#if defined(_DEBUG) && defined(LOG_ENABLE_DBG) && LOG_ENABLE_DBG && 0
static const char *const state_names[] = {
    [STATE_GROUND] = "ground",

    [STATE_ESCAPE] = "escape",
    [STATE_ESCAPE_INTERMEDIATE] = "escape intermediate",

    [STATE_CSI_ENTRY] = "CSI entry",
    [STATE_CSI_PARAM] = "CSI param",
    [STATE_CSI_INTERMEDIATE] = "CSI intermediate",
    [STATE_CSI_IGNORE] = "CSI ignore",

    [STATE_OSC_STRING] = "OSC string",

    [STATE_DCS_ENTRY] = "DCS entry",
    [STATE_DCS_PARAM] = "DCS param",
    [STATE_DCS_INTERMEDIATE] = "DCS intermediate",
    [STATE_DCS_IGNORE] = "DCS ignore",
    [STATE_DCS_PASSTHROUGH] = "DCS passthrough",

    [STATE_SOS_PM_APC_STRING] = "sos/pm/apc string",

    [STATE_UTF8_21] = "UTF8 2-byte 1/2",
    [STATE_UTF8_31] = "UTF8 3-byte 1/3",
    [STATE_UTF8_32] = "UTF8 3-byte 2/3",
};
#endif

#if defined(LOG_ENABLE_DBG) && LOG_ENABLE_DBG
static const char *
esc_as_string(struct terminal *term, uint8_t final)
{
    static char msg[1024];
    int c = snprintf(msg, sizeof(msg), "\\E");

    for (size_t i = 0; i < sizeof(term->vt.private); i++) {
        char value = (term->vt.private >> (i * 8)) & 0xff;
        if (value == 0)
            break;
        c += snprintf(&msg[c], sizeof(msg) - c, "%c", value);
    }

    xassert(term->vt.params.idx == 0);

    snprintf(&msg[c], sizeof(msg) - c, "%c", final);
    return msg;

}
#endif

static void
action_ignore(struct terminal *term)
{
}

static void
action_clear(struct terminal *term)
{
    term->vt.params.idx = 0;
    term->vt.private = 0;
}

static void
action_execute(struct terminal *term, uint8_t c)
{
    LOG_DBG("execute: 0x%02x", c);
    switch (c) {

        /*
         * 7-bit C0 control characters
         */

    case '\0':
        break;

    case '\a':
        /* BEL - bell */
        term_bell(term);
        break;

    case '\b':
        /* backspace */
#if 0
        /*
         * This is the "correct" BS behavior. However, it doesn't play
         * nicely with bw/auto_left_margin, hence the alternative
         * implementation below.
         *
         * Note that it breaks vttest "1. Test of cursor movements ->
         * Test of autowrap"
         */
        term_cursor_left(term, 1);
#else
        if (term->grid->cursor.lcf)
            term->grid->cursor.lcf = false;
        else {
            /* Reverse wrap */
            if (unlikely(term->grid->cursor.point.col == 0) &&
                likely(term->reverse_wrap && term->auto_margin))
            {
                if (term->grid->cursor.point.row <= term->scroll_region.start) {
                    /* Don't wrap past, or inside, the scrolling region(?) */
                } else
                    term_cursor_to(
                        term,
                        term->grid->cursor.point.row - 1,
                        term->cols - 1);
            } else
                term_cursor_left(term, 1);
        }
#endif
        break;

    case '\t': {
        /* HT - horizontal tab */
        int start_col = term->grid->cursor.point.col;
        int new_col = term->cols - 1;

        tll_foreach(term->tab_stops, it) {
            if (it->item > start_col) {
                new_col = it->item;
                break;
            }
        }
        xassert(new_col >= start_col);
        xassert(new_col < term->cols);

        struct row *row = term->grid->cur_row;

        bool emit_tab_char = (row->cells[start_col].wc == 0 ||
                              row->cells[start_col].wc == U' ');

        /* Check if all cells from here until the next tab stop are empty */
        for (const struct cell *cell = &row->cells[start_col + 1];
             cell < &row->cells[new_col];
             cell++)
        {
            if (!(cell->wc == 0 || cell->wc == U' ')) {
                emit_tab_char = false;
                break;
            }
        }

        /*
         * Emit a tab in current cell, and write spaces to the
         * subsequent cells, all the way until the next tab stop.
         */
        if (emit_tab_char) {
            row->dirty = true;

            row->cells[start_col].wc = U'\t';
            row->cells[start_col].attrs.clean = 0;

            for (struct cell *cell = &row->cells[start_col + 1];
                 cell < &row->cells[new_col];
                 cell++)
            {
                cell->wc = U' ';
                cell->attrs.clean = 0;
            }
        }

        /* According to the specification, HT _should_ cancel LCF. But
         * XTerm, and nearly all other emulators, don't. So we follow
         * suit */
        bool lcf = term->grid->cursor.lcf;
        term_cursor_right(term, new_col - start_col);
        term->grid->cursor.lcf = lcf;
        break;
    }

    case '\n':
    case '\v':
    case '\f':
        /* LF - \n - line feed */
        /* VT - \v - vertical tab */
        /* FF - \f - form feed */
        term_linefeed(term);
        break;

    case '\r':
        /* CR - carriage ret */
        term_carriage_return(term);
        break;

    case '\x0e':
        /* SO - shift out */
        term->charsets.selected = G1;
        term->bits_affecting_ascii_printer.charset =
            term->charsets.set[term->charsets.selected] != CHARSET_ASCII;
        term_update_ascii_printer(term);
        break;

    case '\x0f':
        /* SI - shift in */
        term->charsets.selected = G0;
        term->bits_affecting_ascii_printer.charset =
            term->charsets.set[term->charsets.selected] != CHARSET_ASCII;
        term_update_ascii_printer(term);
        break;

        /*
         * 8-bit C1 control characters
         *
         * We ignore these, but keep them here for reference, along
         * with their corresponding 7-bit variants.
         *
         * As far as I can tell, XTerm also ignores these _when in
         * UTF-8 mode_. Which would be the normal mode of operation
         * these days. And since we _only_ support UTF-8...
         */

#if 0
    case '\x84':  /* IND     -> ESC D */
    case '\x85':  /* NEL     -> ESC E */
    case '\x88':  /* Tab Set -> ESC H */
    case '\x8d':  /* RI      -> ESC M */
    case '\x8e':  /* SS2     -> ESC N */
    case '\x8f':  /* SS3     -> ESC O */
    case '\x90':  /* DCS     -> ESC P */
    case '\x96':  /* SPA     -> ESC V */
    case '\x97':  /* EPA     -> ESC W */
    case '\x98':  /* SOS     -> ESC X */
    case '\x9a':  /* DECID   -> ESC Z (obsolete form of CSI c) */
    case '\x9b':  /* CSI     -> ESC [ */
    case '\x9c':  /* ST      -> ESC \ */
    case '\x9d':  /* OSC     -> ESC ] */
    case '\x9e':  /* PM      -> ESC ^ */
    case '\x9f':  /* APC     -> ESC _ */
        break;
#endif

    default:
        break;
    }
}

static void
action_print(struct terminal *term, uint8_t c)
{
    term_reset_grapheme_state(term);
    term->ascii_printer(term, c);
}

static void
action_param_lazy_init(struct terminal *term)
{
    if (term->vt.params.idx == 0) {
        struct vt_param *param = &term->vt.params.v[0];

        term->vt.params.cur = param;
        param->value = 0;
        param->sub.idx = 0;
        param->sub.cur = NULL;
        term->vt.params.idx = 1;
    }
}

static void
action_param_new(struct terminal *term, uint8_t c)
{
    xassert(c == ';');
    action_param_lazy_init(term);

    const size_t max_params
        = sizeof(term->vt.params.v) / sizeof(term->vt.params.v[0]);

    struct vt_param *param;

    if (unlikely(term->vt.params.idx >= max_params)) {
        static bool have_warned = false;
        if (!have_warned) {
            have_warned = true;
            LOG_WARN(
                "unsupported: escape with more than %zu parameters "
                "(will not warn again)",
                sizeof(term->vt.params.v) / sizeof(term->vt.params.v[0]));
        }
        param = &term->vt.params.dummy;
    } else
        param = &term->vt.params.v[term->vt.params.idx++];

    term->vt.params.cur = param;
    param->value = 0;
    param->sub.idx = 0;
    param->sub.cur = NULL;
}

static void
action_param_new_subparam(struct terminal *term, uint8_t c)
{
    xassert(c == ':');
    action_param_lazy_init(term);

    const size_t max_sub_params
        = sizeof(term->vt.params.v[0].sub.value) / sizeof(term->vt.params.v[0].sub.value[0]);

    struct vt_param *param = term->vt.params.cur;
    unsigned *sub_param_value;

    if (unlikely(param->sub.idx >= max_sub_params)) {
        static bool have_warned = false;
        if (!have_warned) {
            have_warned = true;
            LOG_WARN(
                "unsupported: escape with more than %zu sub-parameters "
                "(will not warn again)",
                sizeof(term->vt.params.v[0].sub.value) / sizeof(term->vt.params.v[0].sub.value[0]));
        }

        sub_param_value = &param->sub.dummy;
    } else
        sub_param_value = &param->sub.value[param->sub.idx++];

    param->sub.cur = sub_param_value;
    *sub_param_value = 0;
}

static void
action_param(struct terminal *term, uint8_t c)
{
    action_param_lazy_init(term);
    xassert(term->vt.params.cur != NULL);

    struct vt_param *param = term->vt.params.cur;
    unsigned *value;

    if (unlikely(param->sub.cur != NULL))
        value = param->sub.cur;
    else
        value = &param->value;

    unsigned v = *value;
    v *= 10;
    v += c - '0';
    *value = v;
}

static void
action_collect(struct terminal *term, uint8_t c)
{
    LOG_DBG("collect: %c", c);

    /*
     * Having more than one private is *very* rare. Foot only supports
     * a *single* escape with two privates, and none with three or
     * more.
     *
     * As such, we optimize *reading* the private(s), and *resetting*
     * them (in action_clear()). Writing is ok if it's a bit slow.
     */

    if ((term->vt.private & 0xff) == 0)
        term->vt.private = c;
    else if (((term->vt.private >> 8) & 0xff) == 0)
        term->vt.private |= c << 8;
    else if (((term->vt.private >> 16) & 0xff) == 0)
        term->vt.private |= c << 16;
    else if (((term->vt.private >> 24) & 0xff) == 0)
        term->vt.private |= c << 24;
    else
        LOG_WARN("only four private/intermediate characters supported");
}

UNITTEST
{
    struct terminal term = {.vt = {.private = 0}};
    uint32_t expected = ' ';
    action_collect(&term, ' ');
    xassert(term.vt.private == expected);

    expected |= '/' << 8;
    action_collect(&term, '/');
    xassert(term.vt.private == expected);

    expected |= '<' << 16;
    action_collect(&term, '<');
    xassert(term.vt.private == expected);

    expected |= '?' << 24;
    action_collect(&term, '?');
    xassert(term.vt.private == expected);

    action_collect(&term, '?');
    xassert(term.vt.private == expected);
}

static void
tab_set(struct terminal *term)
{
    int col = term->grid->cursor.point.col;

    if (tll_length(term->tab_stops) == 0 || tll_back(term->tab_stops) < col) {
        tll_push_back(term->tab_stops, col);
        return;
    }

    tll_foreach(term->tab_stops, it) {
        if (it->item < col) {
            continue;
        }
        if (it->item > col) {
            tll_insert_before(term->tab_stops, it, col);
        }
        break;
    }
}

static void
action_esc_dispatch(struct terminal *term, uint8_t final)
{
    LOG_DBG("ESC: %s", esc_as_string(term, final));

    switch (term->vt.private) {
    case 0:
        switch (final) {
        case '7':
            term_save_cursor(term);
            break;

        case '8':
            term_restore_cursor(term, &term->grid->saved_cursor);
            break;

        case 'c':
            term_reset(term, true);
            break;

        case 'n':
            /* LS2 - Locking Shift 2 */
            term->charsets.selected = G2;
            term->bits_affecting_ascii_printer.charset =
                term->charsets.set[term->charsets.selected] != CHARSET_ASCII;
            term_update_ascii_printer(term);
            break;

        case 'o':
            /* LS3 - Locking Shift 3 */
            term->charsets.selected = G3;
            term->bits_affecting_ascii_printer.charset =
                term->charsets.set[term->charsets.selected] != CHARSET_ASCII;
            term_update_ascii_printer(term);
            break;

        case 'D':
            term_linefeed(term);
            break;

        case 'E':
            term_carriage_return(term);
            term_linefeed(term);
            break;

        case 'H':
            tab_set(term);
            break;

        case 'M':
            term_reverse_index(term);
            break;

        case 'N':
            /* SS2 - Single Shift 2 */
            term_single_shift(term, G2);
            break;

        case 'O':
            /* SS3 - Single Shift 3 */
            term_single_shift(term, G3);
            break;

        case '\\':
            /* ST - String Terminator */
            break;

        case '=':
            term->keypad_keys_mode = KEYPAD_APPLICATION;
            break;

        case '>':
            term->keypad_keys_mode = KEYPAD_NUMERICAL;
            break;

        default:
            UNHANDLED();
            break;
        }
        break;  /* private[0] == 0 */

    // Designate character set
    case '(': // G0
    case ')': // G1
    case '*': // G2
    case '+': // G3
        switch (final) {
        case '0': {
            size_t idx = term->vt.private - '(';
            xassert(idx <= G3);
            term->charsets.set[idx] = CHARSET_GRAPHIC;
            term->bits_affecting_ascii_printer.charset =
                term->charsets.set[term->charsets.selected] != CHARSET_ASCII;
            term_update_ascii_printer(term);
            break;
        }

        case 'B': {
            size_t idx = term->vt.private - '(';
            xassert(idx <= G3);
            term->charsets.set[idx] = CHARSET_ASCII;
            term->bits_affecting_ascii_printer.charset =
                term->charsets.set[term->charsets.selected] != CHARSET_ASCII;
            term_update_ascii_printer(term);
            break;
        }
        }
        break;

    case '#':
        switch (final) {
        case '8':  /* DECALN */
            sixel_overwrite_by_rectangle(term, 0, 0, term->rows, term->cols);

            term->scroll_region.start = 0;
            term->scroll_region.end = term->rows;

            for (int r = 0; r < term->rows; r++)
                term_fill(term, r, 0, 'E', term->cols, false);

            term_cursor_home(term);
            break;
        }
        break;  /* private[0] == '#' */

    }
}

static void
action_csi_dispatch(struct terminal *term, uint8_t c)
{
    csi_dispatch(term, c);
}

static void
action_osc_start(struct terminal *term, uint8_t c)
{
    term->vt.osc.idx = 0;
}

static void
action_osc_end(struct terminal *term, uint8_t c)
{
    struct vt *vt = &term->vt;

    if (!osc_ensure_size(term, vt->osc.idx + 1))
        return;

    vt->osc.data[vt->osc.idx] = '\0';
    vt->osc.bel = c == '\a';
    osc_dispatch(term);

    if (unlikely(vt->osc.idx >= 4096)) {
        free(vt->osc.data);
        vt->osc.data = NULL;
        vt->osc.size = 0;
    }
}

static void
action_osc_put(struct terminal *term, uint8_t c)
{
    if (!osc_ensure_size(term, term->vt.osc.idx + 1))
        return;
    term->vt.osc.data[term->vt.osc.idx++] = c;
}

static void
action_hook(struct terminal *term, uint8_t c)
{
    dcs_hook(term, c);
}

static void
action_unhook(struct terminal *term, uint8_t c)
{
    dcs_unhook(term);
}

static void
action_put(struct terminal *term, uint8_t c)
{
    dcs_put(term, c);
}

static void
action_utf8_print(struct terminal *term, char32_t wc)
{
    term_process_and_print_non_ascii(term, wc);
}

static void
action_utf8_21(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 0x1f) << 6) | (utf8[1] & 0x3f)
    term->vt.utf8 = (c & 0x1f) << 6;
}

static void
action_utf8_22(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 0x1f) << 6) | (utf8[1] & 0x3f)
    term->vt.utf8 |= c & 0x3f;
    action_utf8_print(term, term->vt.utf8);
}

static void
action_utf8_31(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 0xf) << 12) | ((utf8[1] & 0x3f) << 6) | (utf8[2] & 0x3f)
    term->vt.utf8 = (c & 0x0f) << 12;
}

static void
action_utf8_32(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 0xf) << 12) | ((utf8[1] & 0x3f) << 6) | (utf8[2] & 0x3f)
    term->vt.utf8 |= (c & 0x3f) << 6;
}

static void
action_utf8_33(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 0xf) << 12) | ((utf8[1] & 0x3f) << 6) | (utf8[2] & 0x3f)
    term->vt.utf8 |= c & 0x3f;

    const char32_t utf32 = term->vt.utf8;
    if (unlikely(utf32 >= 0xd800 && utf32 <= 0xdfff)) {
        /* Invalid sequence - invalid UTF-16 surrogate halves */
        return;
    }

    /* Note: the E0 range contains overlong encodings. We don't try to
       detect, as they'll still decode to valid UTF-32. */

    action_utf8_print(term, term->vt.utf8);
}

static void
action_utf8_41(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 7) << 18) | ((utf8[1] & 0x3f) << 12) | ((utf8[2] & 0x3f) << 6) | (utf8[3] & 0x3f);
    term->vt.utf8 = (c & 0x07) << 18;
}

static void
action_utf8_42(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 7) << 18) | ((utf8[1] & 0x3f) << 12) | ((utf8[2] & 0x3f) << 6) | (utf8[3] & 0x3f);
    term->vt.utf8 |= (c & 0x3f) << 12;
}

static void
action_utf8_43(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 7) << 18) | ((utf8[1] & 0x3f) << 12) | ((utf8[2] & 0x3f) << 6) | (utf8[3] & 0x3f);
    term->vt.utf8 |= (c & 0x3f) << 6;
}

static void
action_utf8_44(struct terminal *term, uint8_t c)
{
    // wc = ((utf8[0] & 7) << 18) | ((utf8[1] & 0x3f) << 12) | ((utf8[2] & 0x3f) << 6) | (utf8[3] & 0x3f);
    term->vt.utf8 |= c & 0x3f;

    const char32_t utf32 = term->vt.utf8;

    if (unlikely(utf32 > 0x10FFFF)) {
        /* Invalid UTF-8 */
        return;
    }

    /* Note: the F0 range contains overlong encodings. We don't try to
       detect, as they'll still decode to valid UTF-32. */

    action_utf8_print(term, term->vt.utf8);
}

IGNORE_WARNING("-Wpedantic")

static enum state
anywhere(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x18:                                           action_execute(term, data);                                       return STATE_GROUND;
    case 0x1a:                                           action_execute(term, data);                                       return STATE_GROUND;
    case 0x1b:                                                                            action_clear(term);              return STATE_ESCAPE;

    /* 8-bit C1 control characters (not supported) */
    case 0x80 ... 0x9f:                                                                                                    return STATE_GROUND;
    }

    return term->vt.state;
}

static enum state
state_ground_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_execute(term, data);                                       return STATE_GROUND;

    /* modified from 0x20..0x7f to 0x20..0x7e, since 0x7f is DEL, which is a zero-width character */
    case 0x20 ... 0x7e:                                  action_print(term, data);                                         return STATE_GROUND;

    case 0xc2 ... 0xdf:                                  action_utf8_21(term, data);                                       return STATE_UTF8_21;
    case 0xe0 ... 0xef:                                  action_utf8_31(term, data);                                       return STATE_UTF8_31;
    case 0xf0 ... 0xf4:                                  action_utf8_41(term, data);                                       return STATE_UTF8_41;
    }

    return anywhere(term, data);
}

static enum state
state_escape_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_execute(term, data);                                       return STATE_ESCAPE;

    case 0x20 ... 0x2f:                                  action_collect(term, data);                                       return STATE_ESCAPE_INTERMEDIATE;
    case 0x30 ... 0x4f:                                  action_esc_dispatch(term, data);                                  return STATE_GROUND;
    case 0x50:                                                                            action_clear(term);              return STATE_DCS_ENTRY;
    case 0x51 ... 0x57:                                  action_esc_dispatch(term, data);                                  return STATE_GROUND;
    case 0x58:                                                                                                             return STATE_SOS_PM_APC_STRING;
    case 0x59:                                           action_esc_dispatch(term, data);                                  return STATE_GROUND;
    case 0x5a:                                           action_esc_dispatch(term, data);                                  return STATE_GROUND;
    case 0x5b:                                                                            action_clear(term);              return STATE_CSI_ENTRY;
    case 0x5c:                                           action_esc_dispatch(term, data);                                  return STATE_GROUND;
    case 0x5d:                                                                            action_osc_start(term, data);    return STATE_OSC_STRING;
    case 0x5e ... 0x5f:                                                                                                    return STATE_SOS_PM_APC_STRING;
    case 0x60 ... 0x7e:                                  action_esc_dispatch(term, data);                                  return STATE_GROUND;
    case 0x7f:                                           action_ignore(term);                                              return STATE_ESCAPE;
    }

    return anywhere(term, data);
}

static enum state
state_escape_intermediate_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_execute(term, data);                                       return STATE_ESCAPE_INTERMEDIATE;

    case 0x20 ... 0x2f:                                  action_collect(term, data);                                       return STATE_ESCAPE_INTERMEDIATE;
    case 0x30 ... 0x7e:                                  action_esc_dispatch(term, data);                                  return STATE_GROUND;
    case 0x7f:                                           action_ignore(term);                                              return STATE_ESCAPE_INTERMEDIATE;
    }

    return anywhere(term, data);
}

static enum state
state_csi_entry_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_execute(term, data);                                       return STATE_CSI_ENTRY;

    case 0x20 ... 0x2f:                                  action_collect(term, data);                                       return STATE_CSI_INTERMEDIATE;
    case 0x30 ... 0x39:                                  action_param(term, data);                                         return STATE_CSI_PARAM;
    case 0x3a:                                           action_param_new_subparam(term, data);                            return STATE_CSI_PARAM;
    case 0x3b:                                           action_param_new(term, data);                                     return STATE_CSI_PARAM;

    case 0x3c ... 0x3f:                                  action_collect(term, data);                                       return STATE_CSI_PARAM;
    case 0x40 ... 0x7e:                                  action_csi_dispatch(term, data);                                  return STATE_GROUND;
    case 0x7f:                                           action_ignore(term);                                              return STATE_CSI_ENTRY;
    }

    return anywhere(term, data);
}

static enum state
state_csi_param_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_execute(term, data);                                       return STATE_CSI_PARAM;

    case 0x20 ... 0x2f:                                  action_collect(term, data);                                       return STATE_CSI_INTERMEDIATE;

    case 0x30 ... 0x39:                                  action_param(term, data);                                         return STATE_CSI_PARAM;
    case 0x3a:                                           action_param_new_subparam(term, data);                            return STATE_CSI_PARAM;
    case 0x3b:                                           action_param_new(term, data);                                     return STATE_CSI_PARAM;

    case 0x3c ... 0x3f:                                                                                                    return STATE_CSI_IGNORE;
    case 0x40 ... 0x7e:                                  action_csi_dispatch(term, data);                                  return STATE_GROUND;
    case 0x7f:                                           action_ignore(term);                                              return STATE_CSI_PARAM;
    }

    return anywhere(term, data);
}

static enum state
state_csi_intermediate_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_execute(term, data);                                       return STATE_CSI_INTERMEDIATE;

    case 0x20 ... 0x2f:                                  action_collect(term, data);                                       return STATE_CSI_INTERMEDIATE;
    case 0x30 ... 0x3f:                                                                                                    return STATE_CSI_IGNORE;
    case 0x40 ... 0x7e:                                  action_csi_dispatch(term, data);                                  return STATE_GROUND;
    case 0x7f:                                           action_ignore(term);                                              return STATE_CSI_INTERMEDIATE;
    }

    return anywhere(term, data);
}

static enum state
state_csi_ignore_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_execute(term, data);                                       return STATE_CSI_IGNORE;

    case 0x20 ... 0x3f:                                  action_ignore(term);                                              return STATE_CSI_IGNORE;
    case 0x40 ... 0x7e:                                                                                                    return STATE_GROUND;
    case 0x7f:                                           action_ignore(term);                                              return STATE_CSI_IGNORE;
    }

    return anywhere(term, data);
}

static enum state
state_osc_string_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */

    /* Note: original was 20-7f, but I changed to 20-ff to include utf-8. Don't forget to add EXECUTE to 8-bit C1 if we implement that. */
    default:                                             action_osc_put(term, data);                                       return STATE_OSC_STRING;

    case 0x07:          action_osc_end(term, data);                                                                        return STATE_GROUND;

    case 0x00 ... 0x06:
    case 0x08 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_ignore(term);                                              return STATE_OSC_STRING;


    case 0x18:
    case 0x1a:          action_osc_end(term, data);      action_execute(term, data);                                       return STATE_GROUND;

    case 0x1b:          action_osc_end(term, data);      action_clear(term);                                               return STATE_ESCAPE;
    }
}

static enum state
state_dcs_entry_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_ignore(term);                                              return STATE_DCS_ENTRY;

    case 0x20 ... 0x2f:                                  action_collect(term, data);                                       return STATE_DCS_INTERMEDIATE;
    case 0x30 ... 0x39:                                  action_param(term, data);                                         return STATE_DCS_PARAM;
    case 0x3a:                                                                                                             return STATE_DCS_IGNORE;
    case 0x3b:                                           action_param_new(term, data);                                     return STATE_DCS_PARAM;
    case 0x3c ... 0x3f:                                  action_collect(term, data);                                       return STATE_DCS_PARAM;
    case 0x40 ... 0x7e:                                                                   action_hook(term, data);         return STATE_DCS_PASSTHROUGH;
    case 0x7f:                                           action_ignore(term);                                              return STATE_DCS_ENTRY;
    }

    return anywhere(term, data);
}

static enum state
state_dcs_param_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_ignore(term);                                              return STATE_DCS_PARAM;

    case 0x20 ... 0x2f:                                  action_collect(term, data);                                       return STATE_DCS_INTERMEDIATE;
    case 0x30 ... 0x39:                                  action_param(term, data);                                         return STATE_DCS_PARAM;
    case 0x3a:                                                                                                             return STATE_DCS_IGNORE;
    case 0x3b:                                           action_param_new(term, data);                                     return STATE_DCS_PARAM;
    case 0x3c ... 0x3f:                                                                                                    return STATE_DCS_IGNORE;
    case 0x40 ... 0x7e:                                                                   action_hook(term, data);         return STATE_DCS_PASSTHROUGH;
    case 0x7f:                                           action_ignore(term);                                              return STATE_DCS_PARAM;
    }

    return anywhere(term, data);
}

static enum state
state_dcs_intermediate_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:                                  action_ignore(term);                                              return STATE_DCS_INTERMEDIATE;

    case 0x20 ... 0x2f:                                  action_collect(term, data);                                       return STATE_DCS_INTERMEDIATE;
    case 0x30 ... 0x3f:                                                                                                    return STATE_DCS_IGNORE;
    case 0x40 ... 0x7e:                                                                   action_hook(term, data);         return STATE_DCS_PASSTHROUGH;
    case 0x7f:                                           action_ignore(term);                                              return STATE_DCS_INTERMEDIATE;
    }

    return anywhere(term, data);
}

static enum state
state_dcs_ignore_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x1f:
    case 0x20 ... 0x7f:                                  action_ignore(term);                                              return STATE_DCS_IGNORE;
    }

    return anywhere(term, data);
}

static enum state
state_dcs_passthrough_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x7e:                                  action_put(term, data);                                           return STATE_DCS_PASSTHROUGH;

    case 0x7f:                                           action_ignore(term);                                              return STATE_DCS_PASSTHROUGH;

    /* Anywhere */
    case 0x18:          action_unhook(term, data);       action_execute(term, data);                                       return STATE_GROUND;
    case 0x1a:          action_unhook(term, data);       action_execute(term, data);                                       return STATE_GROUND;
    case 0x1b:          action_unhook(term, data);                                        action_clear(term);              return STATE_ESCAPE;

    /* 8-bit C1 control characters (not supported) */
    case 0x80 ... 0x9f: action_unhook(term, data);                                                                         return STATE_GROUND;

    default:                                                                                                               return STATE_DCS_PASSTHROUGH;
    }
}

static enum state
state_sos_pm_apc_string_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x00 ... 0x17:
    case 0x19:
    case 0x1c ... 0x7f:                                  action_ignore(term);                                              return STATE_SOS_PM_APC_STRING;
    }

    return anywhere(term, data);
}

static enum state
state_utf8_21_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x80 ... 0xbf:                                  action_utf8_22(term, data);                                       return STATE_GROUND;
    default:            action_utf8_print(term, 0xfffd); return state_ground_switch(term, data);
    }
}

static enum state
state_utf8_31_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x80 ... 0xbf:                                  action_utf8_32(term, data);                                       return STATE_UTF8_32;
    default:            action_utf8_print(term, 0xfffd); return state_ground_switch(term, data);
    }
}

static enum state
state_utf8_32_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x80 ... 0xbf:                                  action_utf8_33(term, data);                                       return STATE_GROUND;
    default:            action_utf8_print(term, 0xfffd); return state_ground_switch(term, data);
    }
}

static enum state
state_utf8_41_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x80 ... 0xbf:                                  action_utf8_42(term, data);                                       return STATE_UTF8_42;
    default:            action_utf8_print(term, 0xfffd); return state_ground_switch(term, data);
    }
}

static enum state
state_utf8_42_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x80 ... 0xbf:                                  action_utf8_43(term, data);                                       return STATE_UTF8_43;
    default:            action_utf8_print(term, 0xfffd); return state_ground_switch(term, data);
    }
}

static enum state
state_utf8_43_switch(struct terminal *term, uint8_t data)
{
    switch (data) {
        /*              exit                             current                          enter                            new state */
    case 0x80 ... 0xbf:                                  action_utf8_44(term, data);                                       return STATE_GROUND;
    default:            action_utf8_print(term, 0xfffd); return state_ground_switch(term, data);
    }
}

UNIGNORE_WARNINGS

void
vt_from_slave(struct terminal *term, const uint8_t *data, size_t len)
{
    enum state current_state = term->vt.state;

    const uint8_t *p = data;
    for (size_t i = 0; i < len; i++, p++) {
        switch (current_state) {
        case STATE_GROUND:              current_state = state_ground_switch(term, *p); break;
        case STATE_ESCAPE:              current_state = state_escape_switch(term, *p); break;
        case STATE_ESCAPE_INTERMEDIATE: current_state = state_escape_intermediate_switch(term, *p); break;
        case STATE_CSI_ENTRY:           current_state = state_csi_entry_switch(term, *p); break;
        case STATE_CSI_PARAM:           current_state = state_csi_param_switch(term, *p); break;
        case STATE_CSI_INTERMEDIATE:    current_state = state_csi_intermediate_switch(term, *p); break;
        case STATE_CSI_IGNORE:          current_state = state_csi_ignore_switch(term, *p); break;
        case STATE_OSC_STRING:          current_state = state_osc_string_switch(term, *p); break;
        case STATE_DCS_ENTRY:           current_state = state_dcs_entry_switch(term, *p); break;
        case STATE_DCS_PARAM:           current_state = state_dcs_param_switch(term, *p); break;
        case STATE_DCS_INTERMEDIATE:    current_state = state_dcs_intermediate_switch(term, *p); break;
        case STATE_DCS_IGNORE:          current_state = state_dcs_ignore_switch(term, *p); break;
        case STATE_DCS_PASSTHROUGH:     current_state = state_dcs_passthrough_switch(term, *p); break;
        case STATE_SOS_PM_APC_STRING:   current_state = state_sos_pm_apc_string_switch(term, *p); break;

        case STATE_UTF8_21:             current_state = state_utf8_21_switch(term, *p); break;
        case STATE_UTF8_31:             current_state = state_utf8_31_switch(term, *p); break;
        case STATE_UTF8_32:             current_state = state_utf8_32_switch(term, *p); break;
        case STATE_UTF8_41:             current_state = state_utf8_41_switch(term, *p); break;
        case STATE_UTF8_42:             current_state = state_utf8_42_switch(term, *p); break;
        case STATE_UTF8_43:             current_state = state_utf8_43_switch(term, *p); break;
        }

        term->vt.state = current_state;
    }
}
