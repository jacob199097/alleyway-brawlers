'use strict';

/**
 * Reads a constant out of one of the game's GDScript files, so the website shows the game's own
 * text (How to Play, the keyword glossary) and can't drift from it.
 *
 *   gdConst(source, 'SECTIONS')   the value of `const SECTIONS := ...` as plain JS
 *
 * It reads literals only: arrays, dictionaries, strings (with \n, \", \uXXXX and line breaks inside
 * them), numbers, true / false / null, and Color("hex"), which becomes "#hex". Comments and trailing
 * commas are fine. Anything else (a function call, a variable) is an error, so a change the site
 * can't follow fails the test (site.test.cjs) instead of showing up wrong.
 */
function gdConst(source, name) {
    const start = new RegExp(`^const ${name}\\b[^=\\n]*=`, 'm').exec(source);
    if (!start) throw new Error(`const ${name} not found`);
    let i = start.index + start[0].length;
    const fail = (what) => {
        const line = source.slice(0, i).split('\n').length;
        throw new Error(`const ${name}, line ${line}: ${what}`);
    };

    const skip = () => {
        for (;;) {
            while (i < source.length && /\s/.test(source[i])) i++;
            if (source[i] === '#') {
                while (i < source.length && source[i] !== '\n') i++;
            } else if (source[i] === '\\' && /\r?\n/.test(source.slice(i + 1, i + 3))) {
                i++;   // (a line continuation)
            } else {
                return;
            }
        }
    };

    const string = () => {
        const quote = source[i++];
        let out = '';
        while (source[i] !== quote) {
            if (i >= source.length) fail('a string never ends');
            if (source[i] !== '\\') {
                out += source[i++];
                continue;
            }
            const c = source[i + 1];
            if (c === 'u') {
                out += String.fromCharCode(parseInt(source.slice(i + 2, i + 6), 16));
                i += 6;
                continue;
            }
            out += { n: '\n', t: '\t', r: '\r' }[c] ?? c;
            i += 2;
        }
        i++;
        return out;
    };

    const value = () => {
        skip();
        const c = source[i];
        if (c === '"' || c === "'") return string();
        if (c === '[') {
            i++;
            const list = [];
            for (;;) {
                skip();
                if (source[i] === ']') {
                    i++;
                    return list;
                }
                list.push(value());
                skip();
                if (source[i] === ',') i++;
                else if (source[i] !== ']') fail('expected , or ]');
            }
        }
        if (c === '{') {
            i++;
            const dict = {};
            for (;;) {
                skip();
                if (source[i] === '}') {
                    i++;
                    return dict;
                }
                const key = value();
                skip();
                if (source[i] !== ':') fail('expected : after a key');
                i++;
                dict[key] = value();
                skip();
                if (source[i] === ',') i++;
                else if (source[i] !== '}') fail('expected , or }');
            }
        }
        const m = /^(?:Color\(\s*"#?([0-9a-fA-F]{6})(?:[0-9a-fA-F]{2})?"\s*\)|-?\d+(?:\.\d+)?|true|false|null)/.exec(source.slice(i, i + 60));
        if (!m) fail(`can't read "${source.slice(i, i + 24).split('\n')[0]}"`);
        i += m[0].length;
        if (m[1]) return '#' + m[1].toLowerCase();
        return m[0] === 'true' ? true : m[0] === 'false' ? false : m[0] === 'null' ? null : Number(m[0]);
    };

    return value();
}

module.exports = { gdConst };
