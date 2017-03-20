module yu.asyncsocket.server.exception;

import yu.asyncsocket.exception;
import yu.exception;

/// SocketServerException : AsyncSocketExceotion
mixin ExceptionBuild!("SocketServer", "AsyncSocket");

/// SocketBindException : SocketServerExceotion
mixin ExceptionBuild!("SocketBind", "SocketServer");