import std.stdio;
import std.functional;
import yu.tools.http1xparser;
import yu.exception;


void on_message_begin(ref HTTP1xParser)
{
    writeln("_on_message_begin");

    writeln(" ");
}

void on_url(ref HTTP1xParser par, ubyte[] data, bool adv)
{
    writeln("_on_url, is NOADVANCE = ", adv);
    writeln("\" ", cast(string) data, " \"");
    writeln("HTTPMethod is = ", par.methodString);
    writeln(" ");
}

void on_status(ref HTTP1xParser par, ubyte[] data, bool adv)
{
    writeln("_on_status, is NOADVANCE = ", adv);
    writeln("\" ", cast(string) data, " \"");
    writeln(" ");
}

void on_header_field(ref HTTP1xParser par, ubyte[] data, bool adv)
{
    static bool frist = true;
    writeln("_on_header_field, is NOADVANCE = ", adv);
    writeln("len = ", data.length);
    writeln("\" ", cast(string) data, " \"");
    if (frist)
    {
        writeln("\t http_major", par.major);
        writeln("\t http_minor", par.minor);
        frist = false;
    }
    writeln(" ");
}

void on_header_value(ref HTTP1xParser par, ubyte[] data, bool adv)
{
    writeln("_on_header_value, is NOADVANCE = ", adv);
    writeln("\" ", cast(string) data, " \"");
    writeln(" ");
}

void on_headers_complete(ref HTTP1xParser par)
{
//	par.stopNow;
    writeln("_on_headers_complete");
    writeln(" ");

}

void on_body(ref HTTP1xParser par, ubyte[] data, bool adv)
{
    writeln("_on_body, is NOADVANCE = ", adv);
    writeln("\" ", cast(string) data, " \"");
    writeln(" ");
}

void on_message_complete(ref HTTP1xParser par)
{
    writeln("_on_message_complete");
    writeln(" ");
}

void on_chunk_header(ref HTTP1xParser par)
{
    writeln("_on_chunk_header");
    writeln(" ");
	par.stopNow;
}

void on_chunk_complete(ref HTTP1xParser par)
{
    writeln("_on_chunk_complete");
    writeln(" ");
}

void main()
{
	 string data = "GET /test HTTP/1.1\r\nUser-Agent: curl/7.18.0 (i486-pc-linux-gnu) libcurl/7.18.0 OpenSSL/0.9.8g zlib/1.2.3.3 libidn/1.1\r\nHost:0.0.0.0=5000\r\nAccept: */*\r\n\r\n";
    HTTP1xParser par = HTTP1xParser();
    par.onMessageBegin = toDelegate(&on_message_begin);
    par.onMessageComplete = toDelegate(&on_message_complete);
    par.onUrl = toDelegate(&on_url);
    par.onStatus = toDelegate(&on_status);
    par.onHeaderField = toDelegate(&on_header_field);
    par.onHeaderValue = toDelegate(&on_header_value);
    par.onChunkHeader = toDelegate(&on_chunk_header);
    par.onChunkComplete = toDelegate(&on_chunk_complete);
    par.onBody = toDelegate(&on_body);

    showException(yuCathException(par.httpParserExecute(cast(ubyte[]) data)));

    par.rest(HTTPType.BOTH);
    data = "POST /post_chunked_all_your_base HTTP/1.1\r\nHost:0.0.0.0=5000\r\nTransfer-Encoding:chunked\r\n\r\n5\r\nhello\r\n";

    auto data2 = "0\r\n\r\n";

    showException(yuCathException(par.httpParserExecute(cast(ubyte[]) data)));
    writeln("data 1 is over!");
    showException(yuCathException(par.httpParserExecute(cast(ubyte[]) data2)));

    string testUrl1 = "http://aa:werwer@www.hostname.co:8086/test?a=b#dadsas";
    ParserdUrl url;
    assert(httpParserURL(testUrl1,url));
    string host =  url.getField(testUrl1,URLFieldsType.UF_HOST);
    writeln("host is : " , host);
    string str = url.getField(testUrl1,URLFieldsType.UF_FRAGMENT);
    writeln("UF_FRAGMENT is : " , str);
    str = url.getField(testUrl1,URLFieldsType.UF_QUERY);
    writeln("UF_QUERY is : " , str);
    str = url.getField(testUrl1,URLFieldsType.UF_USERINFO);
    writeln("UF_USERINFO is : " , str);

    writeln("------------------------------------");
    testUrl1 = "/test?a=b#dadsas";
     assert(httpParserURL(testUrl1,url));
    host =  url.getField(testUrl1,URLFieldsType.UF_HOST);
    writeln("host is : " , host);
    str = url.getField(testUrl1,URLFieldsType.UF_FRAGMENT);
    writeln("UF_FRAGMENT is : " , str);
    str = url.getField(testUrl1,URLFieldsType.UF_QUERY);
    writeln("UF_QUERY is : " , str);
    str = url.getField(testUrl1,URLFieldsType.UF_USERINFO);
    writeln("UF_USERINFO is : " , str);

    writeln("------------------------------------");
    testUrl1 = "ww.du.com/test?a=b#dadsas";
    writeln(httpParserURL!true(testUrl1,url));
    host =  url.getField(testUrl1,URLFieldsType.UF_HOST);
    writeln("host is : " , host);
    str = url.getField(testUrl1,URLFieldsType.UF_FRAGMENT);
    writeln("UF_FRAGMENT is : " , str);
    str = url.getField(testUrl1,URLFieldsType.UF_QUERY);
    writeln("UF_QUERY is : " , str);
    str = url.getField(testUrl1,URLFieldsType.UF_USERINFO);
    writeln("UF_USERINFO is : " , str);
}
