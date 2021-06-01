import std.algorithm.iteration : map;
import std.array : join;

import tokenize;
import state : State;

class Quote {
    Token[] tokens;
    Token[] args;
    State context;//TODO: bind context for closures
    bool hasQuoteSep;
    
    this(Token[] args, Token[] tokens, bool hasQuoteSep = false) {
        this.tokens = tokens;
        this.args = args;
        // if(this.tokens[0].payload) {
            //TODO: make saner
            // clearStack = true;
        // }
        hasQuoteSep = hasQuoteSep;
    }
    
    static Quote join(Quote a, Quote b) {
        import std.stdio;
        assert(!a.hasQuoteSep && !b.hasQuoteSep);
        Token space = { row: 0, col: 0, raw: " ", type: TokenType.WHITESPACE };
        Quote res = new Quote([], a.tokens.dup);
        res.tokens ~= space;
        res.tokens ~= b.tokens;
        return res;
    }
    
    override string toString() {
        import std.conv : to;
        return "[" ~
            to!string(args.map!"a.raw".join) ~
            to!string(tokens.map!"a.raw".join) ~
            "]";
    }
}