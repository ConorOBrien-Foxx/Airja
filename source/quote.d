import std.algorithm.iteration : map;
import std.array : join;

import tokenize;
import state : State;

class Quote {
    Token[] tokens;
    Token[] args;
    State context;//TODO: bind context for closures
    bool clearStack = false;
    
    this(Token[] args, Token[] tokens) {
        this.tokens = tokens;
        this.args = args;
        if(this.tokens[0].payload) {
            //TODO: make saner
            clearStack = true;
        }
    }
    
    override string toString() {
        return "[" ~
            args.map!"a.raw".join ~
            tokens.map!"a.raw".join ~
            "]";
    }
}