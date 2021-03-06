import std.uni : isWhite, isAlpha, isAlphaNum;
import std.ascii : isDigit;
import std.string : strip;
import std.functional : binaryFun;
import std.algorithm.searching : find;
import std.array : insertInPlace, replace;
import std.conv : to, text;
import std.json;

enum TokenType {
    QUOTE_START,        // [
    QUOTE_SEP,          // |
    QUOTE_END,          // ]
    SET_LOCAL,          // @name
    SET_GLOBAL,         // @!name
    SET_FUNCTION,       // @:name
    VALUEOF,            // $name
    COMMENT,            // ;asdf\n
    ARRAY_START,        // {
    ARRAY_END,          // }
    NUMBER,
    OP,
    WORD,
    STRING,
    WHITESPACE,
    UNKNOWN,
    NONE,//used internally
}
bool isQuoteDelimiter(TokenType t) {
    return t == TokenType.QUOTE_START || t == TokenType.QUOTE_END;
}

uint getUint(JSONValue jv) {
    import std.stdio : writeln;
    uint v;
    switch(jv.type) {
        case JSONType.integer:
            v = jv.integer.to!uint;
            break;
        case JSONType.string:
            v = jv.str.to!uint;
            break;
        default:
            writeln("Unexpected JSONType: ", jv.type);
            break;
    }
    return v;
}

struct Token {
    TokenType type;
    dstring raw;
    uint row;
    uint col;
    dstring payload;
    
    JSONValue toJson() {
        return JSONValue([
            "type": JSONValue(to!string(type)),
            "raw": JSONValue(raw),
            "row": JSONValue(row),
            "col": JSONValue(col),
            "payload": JSONValue(payload),
        ]);
    }
    
    deprecated string toReversibleString() {
        return toJson.toString;
    }
    
    static Token none() {
        return Token(TokenType.NONE,"",0,0,"");
    }
    
    static Token fromJSON(JSONValue jv) {
        return Token(
            jv["type"].str.to!TokenType,
            jv["raw"].str.to!dstring,
            jv["row"].getUint,
            jv["col"].getUint,
            jv["payload"].str.to!dstring,
        );
    }
    
    static Token[] JSONToTokenArray(string json) {
        JSONValue values = json.parseJSON;
        Token[] res;
        foreach(JSONValue v; values.array) {
            res ~= Token.fromJSON(v);
        }
        return res;
    }
    
    static Token[] fileToTokenArray(string path) {
        import std.file : readText;
        return JSONToTokenArray(path.readText);
    }
    
    static JSONValue tokenArrayToJson(Token[] tokens) {
        import std.algorithm : map;
        import std.array : array;
        return JSONValue(tokens.map!"a.toJson".array);
    }
    
    static void writeTokenArrayToFile(Token[] tokens, string path) {
        import std.file : write;
        write(path, Token.tokenArrayToJson(tokens).toString());
    }
}

bool isQuoteDelimiter(Token tok) {
    return tok.type.isQuoteDelimiter;
}

dstring[dstring] sourceOps;
void registerOp(ref dstring[dstring] src, dstring op, dstring name) {
    src[op] = name;
}
void registerOp(dstring op, dstring name) {
    registerOp(sourceOps, op, name);
}

shared static this() {
    registerOp("+",  "add");
    registerOp("-",  "sub");
    registerOp("*",  "mul");
    registerOp("/",  "div");
    registerOp("%",  "mod");
    registerOp("!",  "bang");
    registerOp(",",  "pair");
    registerOp(":",  "dup");
    registerOp("\\", "swap");
    registerOp("~",  "drop");
    registerOp("=",  "eq");
    registerOp("???",  "neq");
    registerOp("!=", "neq");
    registerOp("<",  "lt");
    registerOp("<=", "lte");
    registerOp(">",  "gt");
    registerOp(">=", "gte");
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

bool hasPrefix(String, Index)(String s, Index i, String sub) {
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

Token[] parse(string s, dstring[dstring] ops) {
    import std.conv : to;
    return parse(to!dstring(s), ops);
}

Token[] parse(dstring s, dstring[dstring] ops) {
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
    
    dstring readUntil(Index, T)(ref Index i, T c) {
        dstring res = "";
        // writefln("C: %u '%c' %u", i, s[i], c.find(s[i]).length);
        while(i < s.length && c.find(s[i]).length == 0) {
            // writefln("Parsing %u", i);
            res ~= s[i];
            nextChar(i);
        }
        return res;
    }
    dstring readWord(Index)(ref Index i) {
        dstring raw = "";
        if(i < s.length && s[i].isIdentifierHead) {
            raw ~= s[i];
            nextChar(i);
            while(i < s.length && s[i].isIdentifier) {
                raw ~= s[i];
                nextChar(i);
            }
        }
        return raw;
    }
    
    for(uint i = 0; i < s.length; ) {
        Token build = { row: row, col: col, raw: "", type: TokenType.UNKNOWN };
        
        // handle preprocess directive
        if(build.col == 1 && s.hasPrefix(i, "@@"d)) {
            nextChar(i, 2);
            if(s.hasPrefix(i, "op")) {
                nextChar(i, 2);
                if(s[i] == ' ') nextChar(i);
                auto newOp = readUntil(i, [' ', '\n']).strip;
                auto name = readUntil(i, ['\n']).strip;
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
            if(i < s.length && s[i] == 'b') {
                build.raw ~= s[i];
                nextChar(i);
            }
        }
        else if(s[i].isIdentifierHead) {
            build.type = TokenType.WORD;
            build.raw ~= readWord(i);
        }
        else if(s[i] == '"' || s[i] == '\'') {
            build.type = TokenType.STRING;
            dchar delim = s[i];
            build.raw ~= s[i];
            nextChar(i);
            while(i < s.length) {
                build.raw ~= s[i];
                nextChar(i);
                if(s[i - 1] == delim) {
                    if(i < s.length && s[i] == delim) {
                        build.raw ~= s[i];
                        nextChar(i);
                    }
                    else {
                        break;
                    }
                }
            }
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
            if(i < s.length && s[i] == '.') {// clear stack before execution
                build.raw ~= s[i];
                build.payload ~= s[i];
                nextChar(i);
            }
        }
        else if(s[i] == ']') {
            build.type = TokenType.QUOTE_END;
            build.raw ~= s[i];
            nextChar(i);
        }
        else if(s[i] == '(') {
            build.type = TokenType.ARRAY_START;
            build.raw ~= s[i];
            nextChar(i);
        }
        else if(s[i] == ')') {
            build.type = TokenType.ARRAY_END;
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
            build.raw ~= readWord(i);
            build.payload = build.raw[payloadStart..$];
        }
        else if(s[i] == ';') {
            build.type = TokenType.COMMENT;
            build.raw ~= readUntil(i, [ '\n' ]);
        }
        else if(s[i] == '$') {
            uint payloadStart = 1;
            build.type = TokenType.VALUEOF;
            build.raw ~= s[i];
            nextChar(i);
            build.raw ~= readWord(i);
            build.payload = build.raw[1..$];
        }
        else {
            dstring foundOp = "";
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