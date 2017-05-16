module yu.tools.http1xparser.url;

import yu.tools.http1xparser.default_;
import yu.traits;

@trusted :

enum URLFieldsType : ushort
{ 
  UF_SCHEMA           = 0 , 
  UF_HOST             = 1 , 
  UF_PORT             = 2 , 
  UF_PATH             = 3 , 
  UF_QUERY            = 4 , 
  UF_FRAGMENT         = 5 , 
  UF_USERINFO         = 6 , 
  UF_MAX              = 7
}

/* Result structure for httpParserURL().
 *
 * Callers should index into fieldData[] with UF_* values iff field_set
 * has the relevant (1 << UF_*) bit set. As a courtesy to clients (and
 * because we probably have padding left over), we convert any port to
 * a uint16_t.
 */
struct ParserdUrl 
{
  ushort fieldSet;           /* Bitmask of (1 << UF_*) values */
  ushort port;                /* Converted UF_PORT string */

  struct Field {
    ushort off;               /* Offset into buffer in which field starts */
    ushort len;               /* Length of run in buffer */
  } 
  Field[URLFieldsType.UF_MAX] fieldData;

  pragma(inline,true)
  bool hasField(URLFieldsType type) nothrow @nogc
  {
       return (fieldSet & ( 1 << type)) > 0;
  }

  auto getField(CHAR)(CHAR[] url, URLFieldsType type) @nogc nothrow
  {
      size_t max = (fieldData[type].off + fieldData[type].len);
      if(!hasField(type) || max > url.length)
        return (CHAR[]).init;
      return url[fieldData[type].off .. max];
  }
}

//is_connect = true 方法将进行严格检验，如果URL中没有port、schema将导致 httpParserURL 方法失败
bool httpParserURL(bool strict = false, CHAR)(CHAR[] url , out  ParserdUrl u) @nogc nothrow 
                                                                            if(isCharByte!CHAR)
{
  const ubyte[] data = cast(const ubyte[])(url);
  HTTPParserState s;
  size_t p;
  URLFieldsType uf, old_uf;
  bool found_at = false;

  s = strict ? HTTPParserState.s_req_server_start : HTTPParserState.s_req_spaces_before_url;
  old_uf = URLFieldsType.UF_MAX;
  //import std.experimental.logger;
  for (p = 0; p < data.length; p++) with(URLFieldsType){
    const ubyte ch = data[p];
    s = parseURLchar(s, ch);
    //trace("ch == ", cast(char)ch, "    type = ", s);
    /* Figure out the next field that we're operating on */
    switch (s) with(HTTPParserState){
      case s_dead:
        return false;

      /* Skip delimeters */
      case s_req_schema_slash:
      case s_req_schema_slash_slash:
      case s_req_server_start:
      case s_req_query_string_start:
      case s_req_fragment_start:
        continue;

      case s_req_schema:
        uf = UF_SCHEMA;
        break;

      case s_req_server_with_at:
        found_at = true;
        goto case;
      /* FALLTROUGH */
      case s_req_server:
        uf = UF_HOST;
        break;

      case s_req_path:
        uf = UF_PATH;
        break;

      case s_req_query_string:
        uf = UF_QUERY;
        break;

      case s_req_fragment:
        uf = UF_FRAGMENT;
        break;

      default:
        assert(!"Unexpected state");
        return false;
    }

    /* Nothing's changed; soldier on */
    if (uf == old_uf) {
      u.fieldData[uf].len++;
      continue;
    }

    u.fieldData[uf].off = cast(ushort)p;
    u.fieldData[uf].len = 1;

    u.fieldSet |= (1 << uf);
    old_uf = uf;
  }

  /* host must be present if there is a schema */
  /* parsing http:///toto will fail */
  if (u.hasField(URLFieldsType.UF_SCHEMA) && (!u.hasField(URLFieldsType.UF_HOST))) {
    return false;
  }
  if (u.hasField(URLFieldsType.UF_HOST)) {
    if(!parserHost(data, u, found_at)) {
      return false;
    }
  }
  /* CONNECT requests can only contain "hostname:port" */
  if (strict && u.fieldSet != ((1 << URLFieldsType.UF_HOST)|(1 << URLFieldsType.UF_PORT))) {
    return false;
  }

  if (u.hasField(URLFieldsType.UF_PORT)) {
    import core.stdc.stdlib : strtoul;
    /* Don't bother with endp; we've already validated the string */
    const ubyte[] tdata = data[u.fieldData[URLFieldsType.UF_PORT].off..$];
    ulong v = strtoul(cast(const char*)(tdata.ptr), null, 10);

    /* Ports have a max value of 2^16 */
    if (v > ushort.max) return false;
    
    u.port = cast(ushort)v;
  }

  return true;
}

package:

HTTPParserHostState parserHostChar(HTTPParserHostState s, ubyte ch) @nogc nothrow {
  switch(s) with(HTTPParserHostState) 
  {
    case s_http_userinfo:
    case s_http_userinfo_start:
      if (ch == '@') {
        return s_http_host_start;
      }

      if (IS_USERINFO_CHAR2(ch)) {
        return s_http_userinfo;
      }
      break;

    case s_http_host_start:
      if (ch == '[') {
        return s_http_host_v6_start;
      }

      if (IS_HOST_CHAR(ch)) {
        return s_http_host;
      }

      break;

    case s_http_host:
      if (IS_HOST_CHAR(ch)) {
        return s_http_host;
      }
      goto case;
    /* FALLTHROUGH */
    case s_http_host_v6_end:
      if (ch == ':') {
        return s_http_host_port_start;
      }

      break;

    case s_http_host_v6:
      if (ch == ']') {
        return s_http_host_v6_end;
      }
      goto case;
    /* FALLTHROUGH */
    case s_http_host_v6_start:
      if (IS_HEX(ch) || ch == ':' || ch == '.') {
        return s_http_host_v6;
      }

      if (s == s_http_host_v6 && ch == '%') {
        return s_http_host_v6_zone_start;
      }
      break;

    case s_http_host_v6_zone:
      if (ch == ']') {
        return s_http_host_v6_end;
      }
      goto case;
    /* FALLTHROUGH */
    case s_http_host_v6_zone_start:
      /* RFC 6874 Zone ID consists of 1*( unreserved / pct-encoded) */
      if (IS_ALPHANUM(ch) || ch == '%' || ch == '.' || ch == '-' || ch == '_' ||
          ch == '~') {
        return s_http_host_v6_zone;
      }
      break;

    case s_http_host_port:
    case s_http_host_port_start:
      if (mixin(IS_NUM("ch"))) {
        return s_http_host_port;
      }
      break;
    default:
      break;
  }
  return HTTPParserHostState.s_http_host_dead;
}

bool parserHost(const ubyte[] data, ref ParserdUrl u, bool found_at) @nogc nothrow {
  HTTPParserHostState s;

  size_t p;
  size_t buflen = u.fieldData[URLFieldsType.UF_HOST].off + u.fieldData[URLFieldsType.UF_HOST].len;

  assert(u.fieldSet & (1 << URLFieldsType.UF_HOST));

  u.fieldData[URLFieldsType.UF_HOST].len = 0;

  s = found_at ? HTTPParserHostState.s_http_userinfo_start : HTTPParserHostState.s_http_host_start;

  for (p = u.fieldData[URLFieldsType.UF_HOST].off; p < buflen; p++) with (HTTPParserHostState){
    const ubyte ch = data[p];
    const HTTPParserHostState new_s = parserHostChar(s, ch);

    if (new_s == s_http_host_dead) {
      return false;
    }

    switch(new_s) with(URLFieldsType){
      case s_http_host:
        if (s != s_http_host) {
          u.fieldData[UF_HOST].off = cast(ushort)p;
        }
        u.fieldData[UF_HOST].len++;
        break;

      case s_http_host_v6:
        if (s != s_http_host_v6) {
          u.fieldData[UF_HOST].off = cast(ushort)p;
        }
        u.fieldData[UF_HOST].len++;
        break;

      case s_http_host_v6_zone_start:
      case s_http_host_v6_zone:
        u.fieldData[UF_HOST].len++;
        break;

      case s_http_host_port:
        if (s != s_http_host_port) {
          u.fieldData[UF_PORT].off = cast(ushort)p;
          u.fieldData[UF_PORT].len = 0;
          u.fieldSet |= (1 << UF_PORT);
        }
        u.fieldData[UF_PORT].len++;
        break;

      case s_http_userinfo:
        if (s != s_http_userinfo) {
          u.fieldData[UF_USERINFO].off = cast(ushort)p;
          u.fieldData[UF_USERINFO].len = 0;
          u.fieldSet |= (1 << UF_USERINFO);
        }
        u.fieldData[UF_USERINFO].len++;
        break;

      default:
        break;
    }
    s = new_s;
  }

  /* Make sure we don't end somewhere unexpected */
  switch (s) with (HTTPParserHostState){
    case s_http_host_start:
    case s_http_host_v6_start:
    case s_http_host_v6:
    case s_http_host_v6_zone_start:
    case s_http_host_v6_zone:
    case s_http_host_port_start:
    case s_http_userinfo:
    case s_http_userinfo_start:
      return false;
    default:
      break;
  }

  return   true;
}

HTTPParserState parseURLchar(HTTPParserState s, ubyte ch) @nogc nothrow
{
    if (ch == ' ' || ch == '\r' || ch == '\n')
        return HTTPParserState.s_dead;

    version (HTTP_PARSER_STRICT)
    {
        if (ch == '\t' || ch == '\f')
            return s_dead;
    }

    switch (s) with (HTTPParserState)
    {
    case s_req_spaces_before_url:
        /* Proxied requests are followed by scheme of an absolute URI (alpha).
                * All methods except CONNECT are followed by '/' or '*'.
                */
        if (ch == '/' || ch == '*')
            return s_req_path;

        if (mixin(IS_ALPHA("ch")))
            return s_req_schema;
        break;

    case s_req_schema:
        if (mixin(IS_ALPHA("ch")))
            return s;

        if (ch == ':')
            return s_req_schema_slash;
        break;

    case s_req_schema_slash:
        if (ch == '/')
            return s_req_schema_slash_slash;
        break;

    case s_req_schema_slash_slash:
        if (ch == '/')
            return s_req_server_start;
        break;

    case s_req_server_with_at:
        if (ch == '@')
        {
            return s_dead;
        }
        goto case;
        /* FALLTHROUGH */
    case s_req_server_start:
    case s_req_server:
        {
            if (ch == '/')
                return s_req_path;

            if (ch == '?')
                return s_req_query_string_start;

            if (ch == '@')
                return s_req_server_with_at;

            if (IS_USERINFO_CHAR2(ch) || ch == '[' || ch == ']')
                return s_req_server;
        }
        break;

    case s_req_path:
        {
            if (mixin(IS_URL_CHAR("ch")))
                return s;

            switch (ch)
            {
            case '?':
                return s_req_query_string_start;

            case '#':
                return s_req_fragment_start;
            default:
                break;
            }
        }
        break;
    case s_req_query_string_start:
    case s_req_query_string:
        {
            if (mixin(IS_URL_CHAR("ch")))
            {
                return s_req_query_string;
            }

            switch (ch)
            {
            case '?':
                /* allow extra '?' in query string */
                return s_req_query_string;

            case '#':
                return s_req_fragment_start;
            default:
                break;
            }
            break;
        }

    case s_req_fragment_start:
        {
            if (mixin(IS_URL_CHAR("ch")))
                return s_req_fragment;
            switch (ch)
            {
            case '?':
                return s_req_fragment;

            case '#':
                return s;
            default:
                break;
            }
        }
        break;
    case s_req_fragment:
        {
            if (mixin(IS_URL_CHAR("ch")))
                return s;
            switch (ch)
            {
            case '?':
            case '#':
                return s;
            default:
                break;
            }
        }
        break;
    default:
        break;
    }
    /* We should never fall out of the switch above unless there's an error */
    return HTTPParserState.s_dead;
}

pragma(inline, true) bool IS_HEX(ubyte c) nothrow @nogc
{
     bool sum = mixin(IS_NUM("c"));
     c = c | 0x20; 
     return (sum || (c >= 'a' && c <= 'f'));
}

pragma(inline, true) bool IS_HOST_CHAR(ubyte c) nothrow @nogc {
    return (IS_ALPHANUM(c) || (c) == '.' || (c) == '-');
}

pragma(inline, true) bool IS_ALPHANUM(ubyte c) nothrow @nogc {
    bool alpha = mixin(IS_ALPHA("c"));
    bool sum = mixin(IS_NUM("c"));
    return (sum || alpha);
}

pragma(inline, true) bool IS_USERINFO_CHAR2(ubyte c) nothrow @nogc
{
    bool b1 = (c == '%' || c == ';' || c == ':' || c == '&' || c == '='
            || c == '+' || c == '$' || c == ',');
    bool b2 = (c == '-' || '_' == c || '.' == c || '!' == c || '~' == c || '*' == c
            || '\'' == c || '(' == c || ')' == c);
    return (b2 || b1 || IS_ALPHANUM(c));
}

pragma(inline, true)
void STRICT_CHECK(bool istrue)
{
    if(istrue)
        throw new Http1xParserExcetion(HTTPParserErrno.HPE_STRICT);
}
//	string IS_MARK(string c) { return "(" ~ c ~ " == '-' || " ~ c ~ " == '_' || "~ c ~ " == '.' || " ~ c ~ " == '!' || " ~ c ~ " == '~' ||  " ~ c ~ " == '*' ||  " ~ c ~ " == '\'' || " ~ c ~ " == '(' || " ~ c ~ " == ')')";}
string IS_NUM(string c)
{
    return "(" ~ c ~ " >= '0' &&  " ~ c ~ "  <= '9')";
}

string IS_ALPHA(string c)
{
    return "((" ~ c ~ "| 0x20) >= 'a' && (" ~ c ~ " | 0x20) <= 'z')";
}

string IS_URL_CHAR(string c)
{
    return "(!!(cast(uint) (normal_url_char[cast(uint) (" ~ c
        ~ ") >> 3] ) &                  
				(1 << (cast(uint)" ~ c ~ " & 7))))";
}

enum NEW_MESSAGE = "httpShouldKeepAlive() ? (type == HTTPType.REQUEST ? HTTPParserState.s_start_req : HTTPParserState.s_start_res) : HTTPParserState.s_dead";
string CALLBACK_NOTIFY(string code)
{
    string _s = " {if (_on" ~ code ~ " !is null){
               _on" ~ code ~ "(this);  
               if(!handleIng)
	                throw new Http1xParserStopExcetion(HTTPParserErrno.HPE_CB_" ~ code ~ ", p + 1);
                } }";
    return _s;
}

string CALLBACK_NOTIFY_NOADVANCE(string code)
{
    string _s = " {if (_on" ~ code ~ " != null){
	               _on" ~ code ~ "(this); 
                   if(!handleIng)
	                throw new Http1xParserStopExcetion(HTTPParserErrno.HPE_CB_" ~ code ~ ", p);
                   }}";
    return _s;
}

string CALLBACK_DATA(string code)
{
    string _s = "{ if( m" ~ code ~ "Mark != size_t.max && _on" ~ code
        ~ " !is null){
                ulong len = (p - m" ~ code ~ "Mark) ;
                
                if(len > 0) {  
               /* writeln(\"CALLBACK_DATA at  \",__LINE__, \"  " ~ code ~ "\");*/
                ubyte[]  _data =  data[m" ~ code ~ "Mark..p];
                _on"
        ~ code ~ "(this,_data,true);
                 if(!handleIng)
	                throw new Http1xParserStopExcetion(HTTPParserErrno.HPE_CB_"
        ~ code ~ ", p + 1);
                } } m" ~ code ~ "Mark = size_t.max;}";
    return _s;
}

string CALLBACK_DATA_NOADVANCE(string code)
{
    string _s = "{ if(m" ~ code ~ "Mark != size_t.max && _on" ~ code ~ " !is null){
                ulong len = (p - m" ~ code ~ "Mark) ;
                if(len > 0) {  
                 /*writeln(\"CALLBACK_DATA_NOADVANCE at  \",__LINE__, \"  " ~ code ~ "\");*/
                ubyte[]  _data = data[m" ~ code
        ~ "Mark..p];
                _on" ~ code ~ "(this,_data,false);
                 if(!handleIng)
	                throw new Http1xParserStopExcetion(HTTPParserErrno.HPE_CB_" ~ code ~ ", p);
                }}m" ~ code
        ~ "Mark = size_t.max;}";
    return _s;
}

@nogc nothrow unittest{
    string testUrl1 = "http://aa:werwer@www.hostname.co:8086/test?a=b#dadsas";
    ParserdUrl url;
    assert(httpParserURL(testUrl1,url));
    assert(url.hasField(URLFieldsType.UF_SCHEMA));
    assert(url.hasField(URLFieldsType.UF_HOST));
    string host =  url.getField(testUrl1,URLFieldsType.UF_HOST);
    assert(host == "www.hostname.co");
    assert(url.port == 8086);
    assert(url.hasField(URLFieldsType.UF_FRAGMENT));
    string str = url.getField(testUrl1,URLFieldsType.UF_FRAGMENT);
    assert(str == "dadsas");
    str = url.getField(testUrl1,URLFieldsType.UF_QUERY);
    assert(str == "a=b" );
    str = url.getField(testUrl1,URLFieldsType.UF_USERINFO);
    assert(str == "aa:werwer" );
}