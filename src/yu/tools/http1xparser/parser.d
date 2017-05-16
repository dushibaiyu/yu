module yu.tools.http1xparser.parser;

import yu.tools.http1xparser.default_;
import yu.tools.http1xparser.url;

/** ubyte[] 为传过去字段里的位置引用，没有数据拷贝，自己使用的时候注意拷贝数据， 
 bool 此段数据是否完结，可能只是数据的一部分。
 */

alias CallBackData = void delegate(ref HTTP1xParser, ubyte[], bool);
alias CallBackNotify = void delegate(ref HTTP1xParser);

@trusted struct HTTP1xParser
{
    this(HTTPType ty, uint maxHeaderSize = 4096)
    {
        rest(ty, maxHeaderSize);
    }

    pragma(inline, true) @property type()
    {
        return _type;
    }

    pragma(inline, true) @property isUpgrade()
    {
        return _upgrade;
    }

    pragma(inline, true) @property contentLength()
    {
        return _contentLength;
    }

    pragma(inline, true) @property isChunked()
    {
        return (_flags & HTTPParserFlags.F_CHUNKED) == 0 ? false : true;
    }

    pragma(inline, true) @property method()
    {
        return _method;
    }

    pragma(inline, true) @property methodString()
    {
        return method_strings[_method];
    }

     //版本号首位
    pragma(inline, true) @property major()
    {
        return _httpMajor;
    }

    //版本号末尾
    pragma(inline, true) @property minor()
    {
        return _httpMinor;
    }

    pragma(inline, true) @property handleIng()
    {
        return _isHandle;
    }

    pragma(inline, true)  //will throw Http1xParserStopExcetion
    @property stopNow()
    {
        _isHandle = false;
    }

    pragma(inline, true) @property skipBody()
    {
        return _skipBody;
    }

    pragma(inline) @property skipBody(bool skip)
    {
        return _skipBody = skip;
    }

    pragma(inline, true) @property keepalive()
    {
        return _keepAlive;
    }

    /** 回调函数指定 */
    pragma(inline, true) @property onMessageBegin(CallBackNotify cback)
    {
        _onMessageBegin = cback;
    }

    pragma(inline, true) @property onMessageComplete(CallBackNotify cback)
    {
        _onMessageComplete = cback;
    }

    pragma(inline, true) @property onHeaderComplete(CallBackNotify cback)
    {
        _onHeadersComplete = cback;
    }

    pragma(inline, true) @property onChunkHeader(CallBackNotify cback)
    {
        _onChunkHeader = cback;
    }

    pragma(inline, true) @property onChunkComplete(CallBackNotify cback)
    {
        _onChunkComplete = cback;
    }

    pragma(inline, true) @property onUrl(CallBackData cback)
    {
        _onUrl = cback;
    }

    pragma(inline, true) @property onStatus(CallBackData cback)
    {
        _onStatus = cback;
    }

    pragma(inline, true) @property onHeaderField(CallBackData cback)
    {
        _onHeaderField = cback;
    }

    pragma(inline, true) @property onHeaderValue(CallBackData cback)
    {
        _onHeaderValue = cback;
    }

    pragma(inline, true) @property onBody(CallBackData cback)
    {
        _onBody = cback;
    }

    void rest(HTTPType ty, uint maxHeaderSize = 4096)
    {
        type = ty;
        _maxHeaderSize = maxHeaderSize;
        _state = (type == HTTPType.REQUEST ? HTTPParserState.s_start_req : (type == HTTPType.RESPONSE
                ? HTTPParserState.s_start_res : HTTPParserState.s_start_req_or_res));
        _httpErrno = HTTPParserErrno.HPE_OK;
        _flags = HTTPParserFlags.F_ZERO;
        _isHandle = false;
        _skipBody = false;
        _keepAlive = 0x00;
    }

public:

    pragma(inline, true) bool bodyIsFinal()
    {
        return _state == HTTPParserState.s_message_done;
    }

    ulong httpParserExecute(ubyte[] data)
    {
        _isHandle = true;
        scope (exit)
            _isHandle = false;
        ubyte c, ch;
        byte unhexVal;
        size_t mHeaderFieldMark = size_t.max;
        size_t mHeaderValueMark = size_t.max;
        size_t mUrlMark = size_t.max;
        size_t mBodyMark = size_t.max;
        size_t mStatusMark = size_t.max;
        size_t maxP = cast(long) data.length;
        size_t p = 0;
        if (_httpErrno != HTTPParserErrno.HPE_OK)
            return 0;
        if (data.length == 0)
        {
            switch (_state) with (HTTPParserState)
            {
            case s_body_identity_eof:
                /* Use of CALLBACK_NOTIFY() here would erroneously return 1 byte read if
                    * we got paused.
                    */
                mixin(CALLBACK_NOTIFY_NOADVANCE("MessageComplete"));
                return 0;

            case s_dead:
            case s_start_req_or_res:
            case s_start_res:
            case s_start_req:
                return 0;

            default:
                _httpErrno = HTTPParserErrno.HPE_INVALID_EOF_STATE;
                return 1;
            }
        }

        if (_state == HTTPParserState.s_header_field)
            mHeaderFieldMark = 0;
        if (_state == HTTPParserState.s_header_value)
            mHeaderValueMark = 0;
        switch (_state) with (HTTPParserState)
        {
        case s_req_path:
        case s_req_schema:
        case s_req_schema_slash:
        case s_req_schema_slash_slash:
        case s_req_server_start:
        case s_req_server:
        case s_req_server_with_at:
        case s_req_query_string_start:
        case s_req_query_string:
        case s_req_fragment_start:
        case s_req_fragment:
            mUrlMark = 0;
            break;
        case s_res_status:
            mStatusMark = 0;
            break;
        default:
            break;
        }
        for (; p < maxP; ++p)
            with (HTTPParserErrno)
            {
                ch = data[p];
                if (_state <= HTTPParserState.s_headers_done)
                {
                    _nread += 1;
                    if (_nread > _maxHeaderSize)
                        throw new Http1xParserExcetion(HPE_HEADER_OVERFLOW);
                }
                while (true)
                {
                    switch (_state) with (HTTPParserState)
                    {
                    case s_dead:
                        /* this _state is used after a 'Connection: close' message
					 * the parser will error out if it reads another message
					 */
                        if (ch == CR || ch == LF)
                            break;
                        else
                            throw new Http1xParserExcetion(HPE_CLOSED_CONNECTION);
                    case s_start_req_or_res:
                        {
                            if (ch == CR || ch == LF)
                                break;
                            _flags = HTTPParserFlags.F_ZERO;
                            _contentLength = ulong.max;

                            if (ch == 'H')
                            {
                                _state = s_res_or_resp_H;
                                mixin(CALLBACK_NOTIFY("MessageBegin")); // 开始处理
                            }
                            else
                            {
                                type = HTTPType.REQUEST;
                                _state = s_start_req;
                                continue;
                            }
                            break;
                        }
                    case s_res_or_resp_H:
                        if (ch == 'T')
                        {
                            type = HTTPType.RESPONSE;
                            _state = s_res_HT;
                        }
                        else
                        {
                            if (ch != 'E')
                                throw new Http1xParserExcetion(HPE_INVALID_CONSTANT);

                            type = HTTPType.REQUEST;
                            _method = HTTPMethod.HEAD;
                            _index = 2;
                            _state = s_req_method;
                        }
                        break;

                    case s_start_res:
                        {
                            _flags = HTTPParserFlags.F_ZERO;
                            _contentLength = ulong.max;
                            switch (ch)
                            {
                            case 'H':
                                _state = s_res_H;
                                break;

                            case CR:
                            case LF:
                                break;

                            default:
                                throw new Http1xParserExcetion(HPE_INVALID_CONSTANT);
                            }
                            mixin(CALLBACK_NOTIFY("MessageBegin"));
                        }
                        break;
                    case s_res_H:
                        STRICT_CHECK(ch != 'T');
                        _state = s_res_HT;
                        break;

                    case s_res_HT:
                        STRICT_CHECK(ch != 'T');
                        _state = s_res_HTT;
                        break;

                    case s_res_HTT:
                        STRICT_CHECK(ch != 'P');
                        _state = s_res_HTTP;
                        break;

                    case s_res_HTTP:
                        STRICT_CHECK(ch != '/');
                        _state = s_res_first_http_major;
                        break;

                    case s_res_first_http_major:
                        if (ch < '0' || ch > '9')
                            throw new Http1xParserExcetion(HPE_INVALID_VERSION);

                        _httpMajor = cast(ushort)(ch - '0');
                        _state = HTTPParserState.s_res_http_major;
                        break;

                        /* major HTTP version or dot */
                    case s_res_http_major:
                        {
                            if (ch == '.')
                            {
                                _state = s_res_first_http_minor;
                                break;
                            }
                            if (!mixin(IS_NUM("ch")))
                                throw new Http1xParserExcetion(HPE_INVALID_VERSION);

                            _httpMajor *= 10;
                            _httpMajor += ch - '0';

                            if (_httpMajor > 999)
                                throw new Http1xParserExcetion(HPE_INVALID_VERSION);
                        }
                        break;

                        /* first digit of minor HTTP version */
                    case s_res_first_http_minor:
                        if (!mixin(IS_NUM("ch")))
                            throw new Http1xParserExcetion(HPE_INVALID_VERSION);

                        _httpMinor = cast(ushort)(ch - '0');
                        _state = s_res_http_minor;
                        break;

                        /* minor HTTP version or end of request line */
                    case s_res_http_minor:
                        {
                            if (ch == ' ')
                            {
                                _state = s_res_first_status_code;
                                break;
                            }

                            if (!mixin(IS_NUM("ch")))
                                throw new Http1xParserExcetion(HPE_INVALID_VERSION);
                            _httpMinor *= 10;
                            _httpMinor += ch - '0';

                            if (_httpMinor > 999)
                                throw new Http1xParserExcetion(HPE_INVALID_VERSION);
                        }
                        break;

                    case s_res_first_status_code:
                        {
                            if (!mixin(IS_NUM("ch")))
                            {
                                if (ch == ' ')
                                    break;
                                throw new Http1xParserExcetion(HPE_INVALID_STATUS);
                            }
                            _statusCode = ch - '0';
                            _state = s_res_status_code;
                        }
                        break;

                    case s_res_status_code:
                        {
                            if (!mixin(IS_NUM("ch")))
                            {
                                switch (ch)
                                {
                                case ' ':
                                    _state = s_res_status_start;
                                    break;
                                case CR:
                                    _state = s_res_line_almost_done;
                                    break;
                                case LF:
                                    _state = s_header_field_start;
                                    break;
                                default:
                                    throw new Http1xParserExcetion(HPE_INVALID_STATUS);
                                }
                                break;
                            }

                            _statusCode *= 10;
                            _statusCode += ch - '0';

                            if (_statusCode > 999)
                                throw new Http1xParserExcetion(HPE_INVALID_STATUS);
                        }
                        break;

                    case s_res_status_start:
                        {
                            if (ch == CR)
                            {
                                _state = s_res_line_almost_done;
                                break;
                            }

                            if (ch == LF)
                            {
                                _state = s_header_field_start;
                                break;
                            }

                            //MARK(status);
                            if (mStatusMark == size_t.max)
                                mStatusMark = p;
                            _state = s_res_status;
                            _index = 0;
                        }
                        break;

                    case s_res_status:
                        if (ch == CR)
                        {
                            _state = s_res_line_almost_done;
                            mixin(CALLBACK_DATA("Status"));
                            break;
                        }

                        if (ch == LF)
                        {
                            _state = s_header_field_start;
                            mixin(CALLBACK_DATA("Status"));
                            break;
                        }

                        break;

                    case s_res_line_almost_done:
                        STRICT_CHECK(ch != LF);
                        _state = s_header_field_start;
                        break;

                    case s_start_req:
                        {
                            if (ch == CR || ch == LF)
                                break;
                            _flags = HTTPParserFlags.F_ZERO;
                            _contentLength = ulong.max;

                            if (!mixin(IS_ALPHA("ch")))
                                throw new Http1xParserExcetion(HPE_INVALID_METHOD);

                            _index = 1;
                            switch (ch) with (HTTPMethod)
                            {
                            case 'A':
                                _method = ACL;
                                break;
                            case 'B':
                                _method = BIND;
                                break;
                            case 'C':
                                _method = CONNECT; /* or COPY, CHECKOUT */ break;
                            case 'D':
                                _method = DELETE;
                                break;
                            case 'G':
                                _method = GET;
                                break;
                            case 'H':
                                _method = HEAD;
                                break;
                            case 'L':
                                _method = LOCK; /* or LINK */ break;
                            case 'M':
                                _method = MKCOL; /* or MOVE, MKACTIVITY, MERGE, M-SEARCH, MKCALENDAR */ break;
                            case 'N':
                                _method = NOTIFY;
                                break;
                            case 'O':
                                _method = OPTIONS;
                                break;
                            case 'P':
                                _method = POST;
                                /* or PROPFIND|PROPPATCH|PUT|PATCH|PURGE */
                                break;
                            case 'R':
                                _method = REPORT; /* or REBIND */ break;
                            case 'S':
                                _method = SUBSCRIBE; /* or SEARCH */ break;
                            case 'T':
                                _method = TRACE;
                                break;
                            case 'U':
                                _method = UNLOCK; /* or UNSUBSCRIBE, UNBIND, UNLINK */ break;
                            default:
                                throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                            }
                            _state = HTTPParserState.s_req_method;
                            mixin(CALLBACK_NOTIFY("MessageBegin"));
                        }
                        break;

                    case s_req_method:
                        {
                            if (ch == '\0')
                                throw new Http1xParserExcetion(HPE_INVALID_METHOD);

                            string matcher = method_strings[_method];
                            if (ch == ' ' && matcher.length == _index)
                                _state = HTTPParserState.s_req_spaces_before_url;
                            else if (ch == matcher[_index])
                            {
                                /* nada */
                            }
                            else if (_method == HTTPMethod.CONNECT)
                            {
                                if (_index == 1 && ch == 'H')
                                    _method = HTTPMethod.CHECKOUT;
                                else if (_index == 2 && ch == 'P')
                                    _method = HTTPMethod.COPY;
                                else
                                    throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                            }
                            else if (_method == HTTPMethod.MKCOL)
                            {
                                if (_index == 1 && ch == 'O')
                                    _method = HTTPMethod.MOVE;
                                else if (_index == 1 && ch == 'E')
                                    _method = HTTPMethod.MERGE;
                                else if (_index == 1 && ch == '-')
                                    _method = HTTPMethod.MSEARCH;
                                else if (_index == 2 && ch == 'A')
                                    _method = HTTPMethod.MKACTIVITY;
                                else if (_index == 3 && ch == 'A')
                                    _method = HTTPMethod.MKCALENDAR;
                                else
                                    throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                            }
                            else if (_method == HTTPMethod.SUBSCRIBE)
                            {
                                if (_index == 1 && ch == 'E')
                                    _method = HTTPMethod.SEARCH;
                                else
                                    throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                            }
                            else if (_method == HTTPMethod.REPORT)
                            {
                                if (_index == 2 && ch == 'B')
                                    _method = HTTPMethod.REBIND;
                                else
                                    throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                            }
                            else if (_index == 1)
                            {
                                if (_method == HTTPMethod.POST)
                                {
                                    if (ch == 'R')
                                        _method = HTTPMethod.PROPFIND; /* or HTTP_PROPPATCH */
                                    else if (ch == 'U')
                                        _method = HTTPMethod.PUT; /* or HTTP_PURGE */
                                    else if (ch == 'A')
                                        _method = HTTPMethod.PATCH;
                                    else
                                        throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                                }
                                else if (_method == HTTPMethod.LOCK)
                                {
                                    if (ch == 'I')
                                        _method = HTTPMethod.LINK;
                                    else
                                        throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                                }
                            }
                            else if (_index == 2)
                            {
                                if (_method == HTTPMethod.PUT)
                                {
                                    if (ch == 'R')
                                        _method = HTTPMethod.PURGE;
                                    else
                                        throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                                }
                                else if (_method == HTTPMethod.UNLOCK)
                                {
                                    if (ch == 'S')
                                        _method = HTTPMethod.UNSUBSCRIBE;
                                    else if (ch == 'B')
                                        _method = HTTPMethod.UNBIND;
                                    else
                                        throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                                }
                                else
                                    throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                            }
                            else if (_index == 4 && _method == HTTPMethod.PROPFIND && ch == 'P')
                            {
                                _method = HTTPMethod.PROPPATCH;
                            }
                            else if (_index == 3 && _method == HTTPMethod.UNLOCK && ch == 'I')
                            {
                                _method = HTTPMethod.UNLINK;
                            }
                            else
                                throw new Http1xParserExcetion(HPE_INVALID_METHOD);
                            ++_index;
                        }
                        break;

                    case s_req_spaces_before_url:
                        {
                            if (ch == ' ')
                                break;
                            if (mUrlMark == size_t.max)
                                mUrlMark = p;
                            if (_method == HTTPMethod.CONNECT)
                                _state = s_req_server_start;
                            _state = parseURLchar(_state, ch);
                            if (_state == s_dead)
                                throw new Http1xParserExcetion(HPE_INVALID_URL);
                        }
                        break;
                    case s_req_schema:
                    case s_req_schema_slash:
                    case s_req_schema_slash_slash:
                    case s_req_server_start:
                        {
                            switch (ch)
                            {
                            case ' ': /* No whitespace allowed here */
                            case CR:
                            case LF:
                                throw new Http1xParserExcetion(HPE_INVALID_URL);
                            default:
                                _state = parseURLchar(_state, ch);
                                if (_state == s_dead)
                                    throw new Http1xParserExcetion(HPE_INVALID_URL);
                            }
                        }
                        break;
                    case s_req_server:
                    case s_req_server_with_at:
                    case s_req_path:
                    case s_req_query_string_start:
                    case s_req_query_string:
                    case s_req_fragment_start:
                    case s_req_fragment:
                        {
                            switch (ch)
                            {
                            case ' ':
                                _state = s_req_http_start;
                                mixin(CALLBACK_DATA("Url"));
                                break;
                            case CR:
                            case LF:
                                _httpMajor = 0;
                                _httpMinor = 9;
                                _state = (ch == CR) ? s_req_line_almost_done : s_header_field_start;
                                mixin(CALLBACK_DATA("Url"));
                                break;
                            default:
                                _state = parseURLchar(_state, ch);
                                if (_state == s_dead)
                                    throw new Http1xParserExcetion(HPE_INVALID_URL);
                            }
                        }
                        break;
                    case s_req_http_start:
                        switch (ch)
                        {
                        case 'H':
                            _state = s_req_http_H;
                            break;
                        case ' ':
                            break;
                        default:
                            throw new Http1xParserExcetion(HPE_INVALID_CONSTANT);
                        }
                        break;

                    case s_req_http_H:
                        STRICT_CHECK(ch != 'T');
                        _state = s_req_http_HT;
                        break;

                    case s_req_http_HT:
                        STRICT_CHECK(ch != 'T');
                        _state = s_req_http_HTT;
                        break;

                    case s_req_http_HTT:
                        STRICT_CHECK(ch != 'P');
                        _state = s_req_http_HTTP;
                        break;

                    case s_req_http_HTTP:
                        STRICT_CHECK(ch != '/');
                        _state = s_req_first_http_major;
                        break;

                        /* first digit of major HTTP version */
                    case s_req_first_http_major:
                        if (ch < '1' || ch > '9')
                            throw new Http1xParserExcetion(HPE_INVALID_VERSION);

                        _httpMajor = cast(ushort)(ch - '0');
                        _state = s_req_http_major;
                        break;

                        /* major HTTP version or dot */
                    case s_req_http_major:
                        {
                            if (ch == '.')
                            {
                                _state = s_req_first_http_minor;
                                break;
                            }

                            if (!mixin(IS_NUM("ch")))
                                throw new Http1xParserExcetion(HPE_INVALID_VERSION);

                            _httpMajor *= 10;
                            _httpMajor += ch - '0';

                            if (_httpMajor > 999)
                                throw new Http1xParserExcetion(HPE_INVALID_VERSION);
                        }
                        break;
                        /* first digit of minor HTTP version */
                    case s_req_first_http_minor:
                        if (!mixin(IS_NUM("ch")))
                            throw new Http1xParserExcetion(HPE_INVALID_VERSION);

                        _httpMinor = cast(ushort)(ch - '0');
                        _state = s_req_http_minor;
                        break;

                        /* minor HTTP version or end of request line */
                    case s_req_http_minor:
                        {
                            if (ch == CR)
                            {
                                _state = s_req_line_almost_done;
                                break;
                            }

                            if (ch == LF)
                            {
                                _state = s_header_field_start;
                                break;
                            }

                            /* XXX allow spaces after digit? */

                            if (!mixin(IS_NUM("ch")))
                                throw new Http1xParserExcetion(HPE_INVALID_VERSION);

                            _httpMinor *= 10;
                            _httpMinor += ch - '0';

                            if (_httpMinor > 999)
                                throw new Http1xParserExcetion(HPE_INVALID_VERSION);
                        }
                        break;

                        /* end of request line */
                    case s_req_line_almost_done:
                        {
                            if (ch != LF)
                                throw new Http1xParserExcetion(HPE_LF_EXPECTED);

                            _state = s_header_field_start;
                        }
                        break;
                    case s_header_field_start:
                        {
                            if (ch == CR)
                            {
                                _state = s_headers_almost_done;
                                break;
                            }

                            if (ch == LF)
                            {
                                /* they might be just sending \n instead of \r\n so this would be
						 * the second \n to denote the end of headers*/
                                _state = s_headers_almost_done;
                                continue;
                            }

                            c = tokens[ch];

                            if (!c)
                                throw new Http1xParserExcetion(HPE_INVALID_HEADER_TOKEN);

                            if (mHeaderFieldMark == size_t.max)
                                mHeaderFieldMark = p;

                            _index = 0;
                            _state = s_header_field;

                            switch (c) with (HTTPParserHeaderstates)
                            {
                            case 'c':
                                _headerState = h_C;
                                break;

                            case 'p':
                                _headerState = h_matching_proxy_connection;
                                break;

                            case 't':
                                _headerState = h_matching_transfer_encoding;
                                break;

                            case 'u':
                                _headerState = h_matching_upgrade;
                                break;

                            default:
                                _headerState = h_general;
                                break;
                            }
                        }
                        break;
                    case s_header_field:
                        {
                            const long start = p;
                            for (; p < maxP; p++)
                            {
                                ch = data[p];
                                c = tokens[ch];
                                if (!c)
                                    break;

                                switch (_headerState) with (HTTPParserHeaderstates)
                                {
                                case h_general:
                                    break;

                                case h_C:
                                    _index++;
                                    _headerState = (c == 'o' ? h_CO : h_general);
                                    break;

                                case h_CO:
                                    _index++;
                                    _headerState = (c == 'n' ? h_CON : h_general);
                                    break;

                                case h_CON:
                                    _index++;
                                    switch (c)
                                    {
                                    case 'n':
                                        _headerState = h_matching_connection;
                                        break;
                                    case 't':
                                        _headerState = h_matching_content_length;
                                        break;
                                    default:
                                        _headerState = h_general;
                                        break;
                                    }
                                    break;
                                    /* connection */
                                case h_matching_connection:
                                    _index++;
                                    if (_index > CONNECTION.length || c != CONNECTION[_index])
                                    {
                                        _headerState = HTTPParserHeaderstates.h_general;
                                    }
                                    else if (_index == CONNECTION.length - 1)
                                    {
                                        _headerState = h_connection;
                                    }
                                    break;
                                    /* proxy-connection */
                                case h_matching_proxy_connection:
                                    _index++;
                                    if (_index > PROXY_CONNECTION.length
                                            || c != PROXY_CONNECTION[_index])
                                    {
                                        _headerState = h_general;
                                    }
                                    else if (_index == PROXY_CONNECTION.length)
                                    {
                                        _headerState = h_connection;
                                    }
                                    break;
                                    /* content-length */
                                case h_matching_content_length:
                                    _index++;
                                    if (_index > CONTENT_LENGTH.length || c != CONTENT_LENGTH[
                                        _index])
                                    {
                                        _headerState = h_general;
                                    }
                                    else if (_index == CONTENT_LENGTH.length - 1)
                                    {
                                        if (_flags & HTTPParserFlags.F_CONTENTLENGTH)
                                            throw new Http1xParserExcetion(
                                                    HPE_UNEXPECTED_CONTENT_LENGTH);
                                        _headerState = HTTPParserHeaderstates.h_content_length;
                                        _flags |= HTTPParserFlags.F_CONTENTLENGTH;
                                    }
                                    break;
                                    /* transfer-encoding */
                                case h_matching_transfer_encoding:
                                    _index++;
                                    if (_index > TRANSFER_ENCODING.length
                                            || c != TRANSFER_ENCODING[_index])
                                    {
                                        _headerState = h_general;
                                    }
                                    else if (_index == TRANSFER_ENCODING.length - 1)
                                    {
                                        _headerState = h_transfer_encoding;
                                    }
                                    break;

                                    /* upgrade */

                                case h_matching_upgrade:
                                    _index++;
                                    if (_index > UPGRADE.length || c != UPGRADE[_index])
                                    {
                                        _headerState = h_general;
                                    }
                                    else if (_index == UPGRADE.length - 1)
                                    {
                                        _headerState = h_upgrade;
                                    }
                                    break;

                                case h_connection:
                                case h_content_length:
                                case h_transfer_encoding:
                                case h_upgrade:
                                    if (ch != ' ')
                                        _headerState = HTTPParserHeaderstates.h_general;
                                    break;
                                default:
                                    assert(false, "Unknown  _headerState");
                                    //	break;
                                }
                            }
                            _nread += (p - start);
                            if (_nread > _maxHeaderSize)
                                throw new Http1xParserExcetion(HTTPParserErrno.HPE_HEADER_OVERFLOW);
                            if (p == maxP)
                            {
                                --p;
                            }
                            else if (ch == ':')
                            {
                                _state = HTTPParserState.s_header_value_discard_ws;
                                mixin(CALLBACK_DATA("HeaderField"));
                            }
                            else
                                throw new Http1xParserExcetion(HPE_INVALID_HEADER_TOKEN);
                        }
                        break;
                    case s_header_value_discard_ws:
                        if (ch == ' ' || ch == '\t')
                            break;
                        if (ch == CR)
                        {
                            _state = s_header_value_discard_ws_almost_done;
                            break;
                        }
                        if (ch == LF)
                        {
                            _state = s_header_value_discard_lws;
                            break;
                        }
                        goto case;
                        /* FALLTHROUGH */
                    case s_header_value_start:
                        {
                            //MARK(header_value);
                            if (mHeaderValueMark == size_t.max)
                                mHeaderValueMark = p;
                            _state = s_header_value;
                            _index = 0;

                            c = ch | 0x20; //LOWER(ch);
                            switch (_headerState) with (HTTPParserHeaderstates)
                            {
                            case h_upgrade:
                                _flags |= HTTPParserFlags.F_UPGRADE;
                                _headerState = h_general;
                                break;

                            case h_transfer_encoding:
                                /* looking for 'Transfer-Encoding: chunked' */
                                if ('c' == c)
                                {
                                    _headerState = h_matching_transfer_encoding_chunked;
                                }
                                else
                                {
                                    _headerState = h_general;
                                }
                                break;

                            case h_content_length:
                                if (!mixin(IS_NUM("ch")))
                                    throw new Http1xParserExcetion(HPE_INVALID_CONTENT_LENGTH);
                                _contentLength = ch - '0';
                                break;

                            case h_connection:
                                /* looking for 'Connection: keep-alive' */
                                if (c == 'k')
                                {
                                    _headerState = h_matching_connection_keep_alive;
                                    _keepAlive = 0x01;
                                    /* looking for 'Connection: close' */
                                }
                                else if (c == 'c')
                                {
                                    _headerState = h_matching_connection_close;
                                    _keepAlive = 0x02;
                                }
                                else if (c == 'u')
                                {
                                    _headerState = h_matching_connection_upgrade;
                                    _keepAlive = 0x03;
                                }
                                else
                                {
                                    _headerState = h_matching_connection_token;
                                    _keepAlive = 0x04;
                                }
                                break;

                                /* Multi-value `Connection` header */
                            case h_matching_connection_token_start:
                                break;

                            default:
                                _headerState = h_general;
                                break;
                            }
                        }
                        break;
                    case s_header_value:
                        {
                            const long start = p;
                            auto h_state = _headerState;
                            for (; p < maxP; p++)
                            {
                                ch = data[p];
                                if (ch == CR)
                                {
                                    _state = s_header_almost_done;
                                    _headerState = h_state;
                                    mixin(CALLBACK_DATA("HeaderValue"));
                                    break;
                                }

                                if (ch == LF)
                                {
                                    _state = s_header_almost_done;
                                    //COUNT_HEADER_SIZE(p - start);
                                    _nread += (p - start);
                                    if (_nread > _maxHeaderSize)
                                        throw new Http1xParserExcetion(HPE_HEADER_OVERFLOW);
                                    _headerState = h_state;
                                    mixin(CALLBACK_DATA_NOADVANCE("HeaderValue"));
                                    continue;
                                }

                                if (!_lenientHttpHeaders && !(ch == CR
                                        || ch == LF || ch == 9 || (ch > 31 && ch != 127)))
                                    throw new Http1xParserExcetion(HPE_INVALID_HEADER_TOKEN);
                                c = ch | 0x20; //LOWER(ch);
                                switch (h_state) with (HTTPParserHeaderstates)
                                {
                                case h_general:
                                    {
                                        //import std.string;
                                        import core.stdc.string;

                                        size_t limit = maxP - p;
                                        limit = (limit < _maxHeaderSize ? limit : _maxHeaderSize); //MIN(limit, TTPConfig.instance.MaxHeaderSize);
                                        auto str = data[p .. maxP];
                                        auto tptr = cast(ubyte*) memchr(str.ptr, CR, str.length);
                                        auto p_cr = tptr - str.ptr; //str._indexOf(CR); // memchr(p, CR, limit);
                                        tptr = cast(ubyte*) memchr(str.ptr, LF, str.length);
                                        auto p_lf = tptr - str.ptr; //str._indexOf(LF); // memchr(p, LF, limit);
                                        ++p_cr;
                                        ++p_lf;
                                        if (p_cr > 0)
                                        {
                                            if (p_lf > 0 && p_cr >= p_lf)
                                                p += p_lf;
                                            else
                                                p += p_cr;
                                        }
                                        else if (p_lf > 0)
                                        {
                                            p += p_lf;
                                        }
                                        else
                                        {
                                            p = maxP;
                                        }
                                        p -= 2;
                                    }
                                    break;
                                case h_connection:
                                case h_transfer_encoding:
                                    assert(0, "Shouldn't get here.");
                                    //break;

                                case h_content_length:
                                    {
                                        ulong t;

                                        if (ch == ' ')
                                            break;

                                        if (!mixin(IS_NUM("ch")))
                                            throw new Http1xParserExcetion(
                                                    HPE_INVALID_CONTENT_LENGTH);

                                        t = _contentLength;
                                        t *= 10;
                                        t += ch - '0';

                                        /* Overflow? Test against a conservative limit for simplicity. */
                                        if ((ulong.max - 10) / 10 < _contentLength)
                                            throw new Http1xParserExcetion(
                                                    HPE_INVALID_CONTENT_LENGTH);
                                        _contentLength = t;
                                    }
                                    break;
                                    /* Transfer-Encoding: chunked */
                                case h_matching_transfer_encoding_chunked: {
                                    _index++;
                                    if (_index > CHUNKED.length || c != CHUNKED[_index])
                                        h_state = h_general;
                                    else if (_index == CHUNKED.length - 1)
                                        h_state = h_transfer_encoding_chunked;
                                }
                                    break;

                                case HTTPParserHeaderstates.h_matching_connection_token_start:
                                    /* looking for 'Connection: keep-alive' */
                                    if (c == 'k')
                                        h_state = h_matching_connection_keep_alive;
                                    /* looking for 'Connection: close' */
                                    else if (c == 'c')
                                        h_state = h_matching_connection_close;
                                    else if (c == 'u')
                                        h_state = h_matching_connection_upgrade;
                                    else if (tokens[c])
                                        h_state = h_matching_connection_token;
                                    else if (c == ' ' || c == '\t')
                                    {
                                        /* Skip lws */
                                    }
                                    else
                                    {
                                        h_state = h_general;
                                    }
                                    break;
                                    /* looking for 'Connection: keep-alive' */
                                case h_matching_connection_keep_alive:
                                    _index++;
                                    if (_index > KEEP_ALIVE.length || c != KEEP_ALIVE[_index])
                                        h_state = h_matching_connection_token;
                                    else if (_index == KEEP_ALIVE.length - 1)
                                        h_state = h_connection_keep_alive;
                                    break;

                                    /* looking for 'Connection: close' */
                                case h_matching_connection_close:
                                    _index++;
                                    if (_index > CLOSE.length || c != CLOSE[_index])
                                        h_state = h_matching_connection_token;
                                    else if (_index == CLOSE.length - 1)
                                        h_state = h_connection_close;
                                    break;

                                    /* looking for 'Connection: upgrade' */
                                case h_matching_connection_upgrade:
                                    _index++;
                                    if (_index > UPGRADE.length || c != UPGRADE[_index])
                                        h_state = h_matching_connection_token;
                                    else if (_index == UPGRADE.length - 1)
                                        h_state = h_connection_upgrade;
                                    break;

                                case h_matching_connection_token:
                                    if (ch == ',')
                                    {
                                        h_state = h_matching_connection_token_start;
                                        _index = 0;
                                    }
                                    break;

                                case h_transfer_encoding_chunked:
                                    if (ch != ' ')
                                        h_state = h_general;
                                    break;

                                case h_connection_keep_alive:
                                case h_connection_close:
                                case h_connection_upgrade:
                                    if (ch == ',')
                                    {
                                        if (h_state == h_connection_keep_alive)
                                            _flags |= HTTPParserFlags.F_CONNECTION_KEEP_ALIVE;
                                        else if (h_state == h_connection_close)
                                            _flags |= HTTPParserFlags.F_CONNECTION_CLOSE;
                                        else if (h_state == h_connection_upgrade)
                                            _flags |= HTTPParserFlags.F_CONNECTION_UPGRADE;
                                        h_state = h_matching_connection_token_start;
                                        _index = 0;
                                    }
                                    else if (ch != ' ')
                                        h_state = h_matching_connection_token;
                                    break;

                                default:
                                    _state = s_header_value;
                                    h_state = h_general;
                                    break;
                                }
                            }
                            _headerState = h_state;

                            //COUNT_HEADER_SIZE(p - start);
                            _nread += (p - start);
                            if (_nread > _maxHeaderSize)
                                throw new Http1xParserExcetion(HPE_HEADER_OVERFLOW);
                            if (p == maxP)
                                --p;
                            break;
                        }

                    case s_header_almost_done:
                        if (ch != LF)
                            throw new Http1xParserExcetion(HPE_LF_EXPECTED);
                        _state = s_header_value_lws;
                        break;
                    case s_header_value_lws:
                        {
                            if (ch == ' ' || ch == '\t')
                            {
                                _state = s_header_value_start;
                                continue;
                            }

                            /* finished the header */
                            switch (_headerState) with (HTTPParserHeaderstates)
                            {
                            case h_connection_keep_alive:
                                _flags |= HTTPParserFlags.F_CONNECTION_KEEP_ALIVE;
                                break;
                            case h_connection_close:
                                _flags |= HTTPParserFlags.F_CONNECTION_CLOSE;
                                break;
                            case h_transfer_encoding_chunked:
                                _flags |= HTTPParserFlags.F_CHUNKED;
                                break;
                            case h_connection_upgrade:
                                _flags |= HTTPParserFlags.F_CONNECTION_UPGRADE;
                                break;
                            default:
                                break;
                            }

                            _state = s_header_field_start;
                            continue;
                        }

                    case s_header_value_discard_ws_almost_done:
                        {
                            STRICT_CHECK(ch != LF);
                            _state = s_header_value_discard_lws;
                        }
                        break;

                    case s_header_value_discard_lws:
                        {
                            if (ch == ' ' || ch == '\t')
                            {
                                _state = s_header_value_discard_ws;
                                break;
                            }
                            else
                            {
                                switch (_headerState) with (HTTPParserHeaderstates)
                                {
                                case h_connection_keep_alive:
                                    _flags |= HTTPParserFlags.F_CONNECTION_KEEP_ALIVE;
                                    break;
                                case h_connection_close:
                                    _flags |= HTTPParserFlags.F_CONNECTION_CLOSE;
                                    break;
                                case h_connection_upgrade:
                                    _flags |= HTTPParserFlags.F_CONNECTION_UPGRADE;
                                    break;
                                case h_transfer_encoding_chunked:
                                    _flags |= HTTPParserFlags.F_CHUNKED;
                                    break;
                                default:
                                    break;
                                }

                                /* header value was empty */
                                //MARK(header_value);
                                if (mHeaderValueMark == size_t.max)
                                {
                                    mHeaderValueMark = p;
                                }
                                _state = s_header_field_start;
                                mixin(CALLBACK_DATA_NOADVANCE("HeaderValue"));
                                continue;
                            }
                        }
                        //TODO	
                    case s_headers_almost_done:
                        {
                            STRICT_CHECK(ch != LF);

                            if (_flags & HTTPParserFlags.F_TRAILING)
                            {
                                /* End of a chunked request */
                                _state = s_message_done;
                                mixin(CALLBACK_NOTIFY_NOADVANCE("ChunkComplete"));
                                continue;
                            }

                            /* Cannot use chunked encoding and a content-length header together
					 per the HTTP specification. */
                            if ((_flags & HTTPParserFlags.F_CHUNKED)
                                    && (_flags & HTTPParserFlags.F_CONTENTLENGTH))
                                throw new Http1xParserExcetion(HPE_UNEXPECTED_CONTENT_LENGTH);
                            _state = s_headers_done;

                            /* Set this here so that on_headers_complete() callbacks can see it */
                            _upgrade = ((_flags & (HTTPParserFlags.F_UPGRADE | HTTPParserFlags.F_CONNECTION_UPGRADE)) == (
                                    HTTPParserFlags.F_UPGRADE | HTTPParserFlags.F_CONNECTION_UPGRADE)
                                    || _method == HTTPMethod.CONNECT);
                            {
                                if (_keepAlive == 0x00 && _httpMinor == 0 && _httpMajor == 1)
                                {
                                    _keepAlive = 0x02;
                                }
                                else
                                {
                                    _keepAlive = 0x01;
                                }
                                if (_onHeadersComplete !is null)
                                {
                                    _onHeadersComplete(this);
                                    if (!handleIng)
                                        throw new Http1xParserStopExcetion(HPE_CB_HeadersComplete,
                                                p + 1);
                                    if (skipBody)
                                        _flags |= HTTPParserFlags.F_SKIPBODY;
                                }
                            }
                            continue;
                        }
                    case s_headers_done:
                        {
                            int hasBody;
                            STRICT_CHECK(ch != LF);

                            _nread = 0;
                            //int chunked = _flags & HTTPParserFlags.F_CHUNKED ;
                            //error("s_headers_done is chunked : ", chunked);
                            hasBody = _flags & HTTPParserFlags.F_CHUNKED
                                || (_contentLength > 0 && _contentLength != ULLONG_MAX);
                            if (_upgrade && (_method == HTTPMethod.CONNECT
                                    || (_flags & HTTPParserFlags.F_SKIPBODY) || !hasBody))
                            {
                                /* Exit, the rest of the message is in a different protocol. */
                                _state = mixin(NEW_MESSAGE);
                                mixin(CALLBACK_NOTIFY("MessageComplete"));
                                return (p + 1);
                            }

                            if (_flags & HTTPParserFlags.F_SKIPBODY)
                            {
                                _state = mixin(NEW_MESSAGE);
                                mixin(CALLBACK_NOTIFY("MessageComplete"));
                            }
                            else if (_flags & HTTPParserFlags.F_CHUNKED)
                            {
                                /* chunked encoding - ignore Content-Length header */
                                _state = s_chunk_size_start;
                            }
                            else
                            {
                                if (_contentLength == 0)
                                {
                                    /* Content-Length header given but zero: Content-Length: 0\r\n */
                                    _state = mixin(NEW_MESSAGE);
                                    mixin(CALLBACK_NOTIFY("MessageComplete"));
                                }
                                else if (_contentLength != ULLONG_MAX)
                                {
                                    /* Content-Length header given and non-zero */
                                    _state = s_body_identity;
                                }
                                else
                                {
                                    if (!httpMessageNeedsEof())
                                    {
                                        /* Assume content-length 0 - read the next */
                                        _state = mixin(NEW_MESSAGE);
                                        mixin(CALLBACK_NOTIFY("MessageComplete"));
                                    }
                                    else
                                    {
                                        /* Read body until EOF */
                                        _state = s_body_identity_eof;
                                    }
                                }
                            }
                            break;
                        }

                    case s_body_identity:
                        {
                            ulong to_read = _contentLength < cast(ulong)(maxP - p) ? _contentLength
                                : cast(ulong)(maxP - p);

                            assert(_contentLength != 0 && _contentLength != ULLONG_MAX);

                            /* The difference between advancing _contentLength and p is because
					 * the latter will automaticaly advance on the next loop iteration.
					 * Further, if _contentLength ends up at 0, we want to see the last
					 * byte again for our message complete callback.
					 */
                            //MARK(body);

                            if (mBodyMark == size_t.max)
                                mBodyMark = p;
                            _contentLength -= to_read;
                            p += to_read - 1;

                            if (_contentLength == 0)
                            {
                                _state = s_message_done;

                                /* Mimic CALLBACK_DATA_NOADVANCE() but with one extra byte.
						 *
						 * The alternative to doing this is to wait for the next byte to
						 * trigger the data callback, just as in every other case. The
						 * problem with this is that this makes it difficult for the test
						 * harness to distinguish between complete-on-EOF and
						 * complete-on-length. It's not clear that this distinction is
						 * important for applications, but let's keep it for now.
						 */
                                if (mBodyMark != size_t.max && _onBody !is null)
                                {
                                    ubyte[] _data = data[mBodyMark .. p + 1];
                                    _onBody(this, _data, true);
                                    if (!handleIng)
                                        throw new Http1xParserStopExcetion(HPE_CB_Body, p + 1);
                                }
                                mBodyMark = size_t.max;
                                continue;
                            }
                        }
                        break;
                        /* read until EOF */
                    case s_body_identity_eof:
                        //MARK(body);
                        if (mBodyMark == size_t.max)
                            mBodyMark = p;
                        p = maxP - 1;
                        break;

                    case s_message_done:
                        _state = mixin(NEW_MESSAGE);
                        mixin(CALLBACK_NOTIFY("MessageComplete"));
                        if (_upgrade) /* Exit, the rest of the message is in a different protocol. */
                            return (p + 1);
                        break;

                    case s_chunk_size_start:
                        {
                            assert(_nread == 1);
                            assert(_flags & HTTPParserFlags.F_CHUNKED);

                            unhexVal = unhex[ch];
                            if (unhexVal == -1)
                                throw new Http1xParserExcetion(HPE_INVALID_CHUNK_SIZE);

                            _contentLength = unhexVal;
                            _state = s_chunk_size;
                        }
                        break;
                    case s_chunk_size:
                        {
                            ulong t;

                            assert(_flags & HTTPParserFlags.F_CHUNKED);

                            if (ch == CR)
                            {
                                _state = s_chunk_size_almost_done;
                                break;
                            }

                            unhexVal = unhex[ch];

                            if (unhexVal == -1)
                            {
                                if (ch == ';' || ch == ' ')
                                {
                                    _state = s_chunk_parameters;
                                    break;
                                }
                                throw new Http1xParserExcetion(HPE_INVALID_CHUNK_SIZE);
                            }

                            t = _contentLength;
                            t *= 16;
                            t += unhexVal;

                            /* Overflow? Test against a conservative limit for simplicity. */
                            if ((ULLONG_MAX - 16) / 16 < _contentLength)
                                throw new Http1xParserExcetion(HPE_INVALID_CONTENT_LENGTH);

                            _contentLength = t;
                            break;
                        }

                    case s_chunk_parameters:
                        {
                            assert(_flags & HTTPParserFlags.F_CHUNKED);
                            /* just ignore this shit. TODO check for overflow */
                            if (ch == CR)
                            {
                                _state = s_chunk_size_almost_done;
                                break;
                            }
                        }
                        break;

                    case s_chunk_size_almost_done:
                        {
                            assert(_flags & HTTPParserFlags.F_CHUNKED);
                            STRICT_CHECK(ch != LF);

                            _nread = 0;

                            if (_contentLength == 0)
                            {
                                _flags |= HTTPParserFlags.F_TRAILING;
                                _state = s_header_field_start;
                            }
                            else
                            {
                                _state = s_chunk_data;
                            }
                            mixin(CALLBACK_NOTIFY("ChunkHeader"));
                        }
                        break;
                    case s_chunk_data:
                        {
                            ulong to_read = _contentLength < cast(ulong)(maxP - p) ? _contentLength
                                : cast(ulong)(maxP - p);

                            assert(_flags & HTTPParserFlags.F_CHUNKED);
                            assert(_contentLength != 0 && _contentLength != ULLONG_MAX);

                            /* See the explanation in s_body_identity for why the content
					 * length and data pointers are managed this way.
					 */
                            //MARK(body);
                            if (mBodyMark == size_t.max)
                                mBodyMark = p;
                            _contentLength -= to_read;
                            p += to_read - 1;

                            if (_contentLength == 0)
                                _state = HTTPParserState.s_chunk_data_almost_done;
                        }
                        break;
                    case s_chunk_data_almost_done:
                        assert(_flags & HTTPParserFlags.F_CHUNKED);
                        assert(_contentLength == 0);
                        STRICT_CHECK(ch != CR);
                        _state = s_chunk_data_done;
                        mixin(CALLBACK_DATA("Body"));
                        break;

                    case HTTPParserState.s_chunk_data_done:
                        assert(_flags & HTTPParserFlags.F_CHUNKED);
                        STRICT_CHECK(ch != LF);
                        _nread = 0;
                        _state = HTTPParserState.s_chunk_size_start;
                        mixin(CALLBACK_NOTIFY("ChunkComplete"));
                        break;

                    default:
                        throw new Http1xParserExcetion(HPE_INVALID_INTERNAL_STATE);
                    }
                    break;
                }
            }

        assert(((mHeaderFieldMark != size_t.max ? 1
                : 0) + (mHeaderValueMark != size_t.max ? 1
                : 0) + (mUrlMark != size_t.max ? 1 : 0) + (mBodyMark != size_t.max
                ? 1 : 0) + (mStatusMark != size_t.max ? 1 : 0)) <= 1);

        mixin(CALLBACK_DATA_NOADVANCE("HeaderField")); //最后没找到
        mixin(CALLBACK_DATA_NOADVANCE("HeaderValue"));
        mixin(CALLBACK_DATA_NOADVANCE("Url"));
        mixin(CALLBACK_DATA_NOADVANCE("Body"));
        mixin(CALLBACK_DATA_NOADVANCE("Status"));

        return data.length;
    }

protected:
    pragma(inline, true) @property type(HTTPType ty)
    {
        _type = ty;
    }

    pragma(inline) bool httpMessageNeedsEof()
    {
        if (type == HTTPType.REQUEST)
            return false;

        /* See RFC 2616 section 4.4 */
        if (_statusCode / 100 == 1 || /* 1xx e.g. Continue */
                _statusCode == 204 || /* No Content */
                _statusCode == 304
                || /* Not Modified */
                _flags & HTTPParserFlags.F_SKIPBODY)
            return false; /* response to a HEAD request */

        if ((_flags & HTTPParserFlags.F_CHUNKED) || _contentLength != ULLONG_MAX)
            return false;
        return true;
    }

    pragma(inline) bool httpShouldKeepAlive()
    {
        if (_httpMajor > 0 && _httpMinor > 0)
        {
            /* HTTP/1.1 */
            if (_flags & HTTPParserFlags.F_CONNECTION_CLOSE)
                return false;
        }
        else
        {
            /* HTTP/1.0 or earlier */
            if (!(_flags & HTTPParserFlags.F_CONNECTION_KEEP_ALIVE))
                return false;
        }
        return !httpMessageNeedsEof();
    }

protected:
    CallBackNotify _onMessageBegin;

    CallBackNotify _onHeadersComplete;

    CallBackNotify _onMessageComplete;

    CallBackNotify _onChunkHeader;

    CallBackNotify _onChunkComplete;

    CallBackData _onUrl;

    CallBackData _onStatus;

    CallBackData _onHeaderField;

    CallBackData _onHeaderValue;

    CallBackData _onBody;

private:
    HTTPType _type = HTTPType.BOTH;
    HTTPParserFlags _flags = HTTPParserFlags.F_ZERO;
    HTTPParserState _state = HTTPParserState.s_start_req_or_res;
    HTTPParserHeaderstates _headerState;
    uint _index;
    uint _lenientHttpHeaders;
    uint _nread;
    ulong _contentLength;
    ushort _httpMajor;
    ushort _httpMinor;
    uint _statusCode; /* responses only */
    HTTPMethod _method; /* requests only */
    HTTPParserErrno _httpErrno = HTTPParserErrno.HPE_OK;
    /* 1 = Upgrade header was present and the parser has exited because of that.
	 * 0 = No upgrade header present.
	 * Should be checked when http_parser_execute() returns in addition to
	 * error checking.
	 */
    bool _upgrade;

    bool _isHandle = false;

    bool _skipBody = false;

    ubyte _keepAlive = 0x00;

    uint _maxHeaderSize = 4096;
}



unittest
{
    import std.stdio;
    import std.functional;
    import yu.exception;

    writeln("\n\n\n");

    void on_message_begin(ref HTTP1xParser)
    {
        writeln("_onMessageBegin");
        writeln(" ");
    }

    void on_url(ref HTTP1xParser par, ubyte[] data, bool adv)
    {
        writeln("_onUrl, is NOADVANCE = ", adv);
        writeln("\" ", cast(string) data, " \"");
        writeln("HTTPMethod is = ", par.methodString);
        writeln(" ");
    }

    void on_status(ref HTTP1xParser par, ubyte[] data, bool adv)
    {
        writeln("_onStatus, is NOADVANCE = ", adv);
        writeln("\" ", cast(string) data, " \"");
        writeln(" ");
    }

    void on_header_field(ref HTTP1xParser par, ubyte[] data, bool adv)
    {
        static bool frist = true;
        writeln("_onHeaderField, is NOADVANCE = ", adv);
        writeln("len = ", data.length);
        writeln("\" ", cast(string) data, " \"");
        if (frist)
        {
            writeln("\t _httpMajor", par.major);
            writeln("\t _httpMinor", par.minor);
            frist = false;
        }
        writeln(" ");
    }

    void on_header_value(ref HTTP1xParser par, ubyte[] data, bool adv)
    {
        writeln("_onHeaderValue, is NOADVANCE = ", adv);
        writeln("\" ", cast(string) data, " \"");
        writeln(" ");
    }

    void on_headers_complete(ref HTTP1xParser par)
    {
        writeln("_onHeadersComplete");
        writeln(" ");
    }

    void on_body(ref HTTP1xParser par, ubyte[] data, bool adv)
    {
        writeln("_onBody, is NOADVANCE = ", adv);
        writeln("\" ", cast(string) data, " \"");
        writeln(" ");
    }

    void on_message_complete(ref HTTP1xParser par)
    {
        writeln("_onMessageComplete");
        writeln(" ");
    }

    void on_chunk_header(ref HTTP1xParser par)
    {
        writeln("_onChunkHeader");
        writeln(" ");
    }

    void on_chunk_complete(ref HTTP1xParser par)
    {
        writeln("_onChunkComplete");
        writeln(" ");
    }

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

    yuCathException!false(par.httpParserExecute(cast(ubyte[]) data));

    par.rest(HTTPType.BOTH);
    data = "POST /post_chunked_all_your_base HTTP/1.1\r\nHost:0.0.0.0=5000\r\nTransfer-Encoding:chunked\r\n\r\n5\r\nhello\r\n";

    auto data2 = "0\r\n\r\n";

    yuCathException!false(par.httpParserExecute(cast(ubyte[]) data));
    writeln("data 1 is over!");
    yuCathException!false(par.httpParserExecute(cast(ubyte[]) data2));
}
