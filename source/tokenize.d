import std.uni : isWhite, isAlpha, isAlphaNum;
import std.ascii : isDigit;
import std.string : strip;
import std.functional : binaryFun;
import std.algorithm.searching : find;
import std.array : insertInPlace;

enum TokenType {
    QUOTE_START,        // [
    QUOTE_SEP,          // |
    QUOTE_END,          // ]
    SET_LOCAL,          // @name
    SET_GLOBAL,         // @!name
    SET_FUNCTION,       // @:name    
    NUMBER,
    OP,
    WORD,
    STRING,
    WHITESPACE,
    UNKNOWN
}
bool isQuoteDelimiter(TokenType t) {
    return t == TokenType.QUOTE_START || t == TokenType.QUOTE_END;
}
struct Token {
    TokenType type;
    string raw;
    uint row;
    uint col;
    string payload;
}
bool isQuoteDelimiter(Token tok) {
    return tok.type.isQuoteDelimiter;
}

string[string] sourceOps;
void registerOp(ref string[string] src, string op, string name) {
    src[op] = name;
}
void registerOp(string op, string name) {
    registerOp(sourceOps, op, name);
}

shared static this() {
    registerOp("+", "add");
    registerOp("-", "sub");
    registerOp("*", "mul");
    registerOp("/", "div");
    registerOp("!", "opbang");
    registerOp(",", "pair");
    registerOp(":", "dup");
}

void insertSorted(alias less = "a < b", Range, Cell)(ref Range src, Cell toInsert) {
    alias lessFn = binaryFun!less;
    for(int i = 0; i < src.length; i++) {
        if(!lessFn(src[i], toInsert)) {
            src.insertInPlace(i, toInsert);
            break;
        }
    }
}

bool hasPrefix(Index)(string s, Index i, string sub) {
    for(uint j = 0; j < sub.length; j++) {
        if(i + j >= s.length)   return false;
        if(s[i + j] != sub[j])  return false;
    }
    return true;
}

bool isIdentifierHead(T)(T c) {
    return c.isAlpha;
}
bool isIdentifier(T)(T c) {
    return c.isAlphaNum || c == '_';
}

Token[] parse(string s) {
    return parse(s, sourceOps.dup);
}

Token[] parse(string s, string[string] ops) {
    import std.stdio;
    
    Token[] res;
    uint row = 1;
    uint col = 1;
    
    void advanceRowCol(T)(T i) {
        if(i >= s.length) return;
        if(s[i] == '\n') {
            row++;
            col = 1;
        }
        else {
            col++;
        }
    }
    
    void nextChar(Count, Index)(ref Index i, Count n = 1) {
        foreach(j; 0..n) {
            advanceRowCol(i);
            i++;
        }
    }
    
    string readUntil(Index, T)(ref Index i, T c) {
        string res = "";
        // writefln("C: %u '%c' %u", i, s[i], c.find(s[i]).length);
        while(i < s.length && c.find(s[i]).length == 0) {
            // writefln("Parsing %u", i);
            res ~= s[i];
            nextChar(i);
        }
        return res;
    }
    
    for(uint i = 0; i < s.length; ) {
        Token build = { row: row, col: col, raw: "", type: TokenType.UNKNOWN };
        
        // handle preprocess directive
        if(build.col == 1 && s.hasPrefix(i, "@@")) {
            nextChar(i, 2);
            if(s.hasPrefix(i, "op")) {
                nextChar(i, 2);
                if(s[i] == ' ') nextChar(i);
                string newOp = readUntil(i, [' ', '\n']).strip;
                string name = readUntil(i, ['\n']).strip;
                registerOp(ops, newOp, name);
                // insertSorted!"a.length > b.length"(ops, newOp.strip);
            }
            else {
                // unknown preprocess directive
                // TODO: throw error
                return null;
            }
            
            // skip over newline
            readUntil(i, ['\n']);
            nextChar(i);
            continue;
        }
        
        // handle normal token
        if(s[i].isWhite) {
            build.type = TokenType.WHITESPACE;
            while(i < s.length && s[i].isWhite) {
                build.raw ~= s[i];
                nextChar(i);
            }
        }
        else if(s[i].isDigit) {
            build.type = TokenType.NUMBER;
            //TODO: allow decimals
            while(i < s.length && s[i].isDigit) {
                build.raw ~= s[i];
                nextChar(i);
            }
        }
        else if(s[i].isIdentifierHead) {
            build.type = TokenType.WORD;
            while(i < s.length && s[i].isIdentifier) {
                build.raw ~= s[i];
                nextChar(i);
            }
        }
        else if(s[i] == '"') {
            build.type = TokenType.STRING;
            build.raw ~= '"';
            nextChar(i);
            while(i < s.length) {
                build.raw ~= s[i];
                nextChar(i);
                if(s[i - 1] == '"') {
                    if(i < s.length && s[i] == '"') {
                        build.raw ~= s[i];
                        nextChar(i);
                    }
                    else {
                        break;
                    }
                }
            }
            // build.raw ~= s[i];
            // nextChar(i);
        }
        else if(s[i] == '[') {
            build.type = TokenType.QUOTE_START;
            build.raw ~= s[i];
            nextChar(i);
        }
        else if(s[i] == '|') {
            build.type = TokenType.QUOTE_SEP;
            build.raw ~= s[i];
            nextChar(i);
        }
        else if(s[i] == ']') {
            build.type = TokenType.QUOTE_END;
            build.raw ~= s[i];
            nextChar(i);
        }
        else if(s[i] == '@') {
            uint payloadStart = 1;
            build.type = TokenType.SET_LOCAL;
            build.raw ~= s[i];
            nextChar(i);
            if(s[i] == ':') {
                build.type = TokenType.SET_FUNCTION;
                build.raw ~= s[i];
                nextChar(i);
                payloadStart++;
            }
            if(i < s.length && s[i].isIdentifierHead) {
                build.raw ~= s[i];
                nextChar(i);
                while(i < s.length && s[i].isIdentifier) {
                    build.raw ~= s[i];
                    nextChar(i);
                }
            }
            build.payload = build.raw[payloadStart..$];
        }
        else {
            string foundOp = "";
            foreach(op, name; ops) {
                // writeln(name, op);
                if(s.hasPrefix(i, op) && op.length > foundOp.length) {
                    foundOp = op;
                }
            }
            
            if(foundOp.length != 0) {
                build.type = TokenType.OP;
                build.raw ~= foundOp;
                build.payload = ops[foundOp];
                nextChar(i, foundOp.length);
            }
            else {
                //build.type = TokenType.UNKNOWN
                build.raw ~= s[i];
                nextChar(i);
            }
        }
        res ~= build;
    }
    return res;
}