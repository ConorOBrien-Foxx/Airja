import std.algorithm.iteration : map;
import std.array : join;

import tokenize;

class Quote {
    Token[] tokens;
    
    this(Token[] tokens) {
        this.tokens = tokens;
    }
    
    override string toString() {
        return "[" ~ tokens.map!"a.raw".join ~ "]";
    }
}