module yu.asyncsocket.exception;

import yu.exception;

/// AsyncSocketException : YuExceotion
mixin ExceptionBuild!("AsyncSocket", "Yu");

/// ConnectedException : AsyncSocketExceotion
mixin ExceptionBuild!("Connected", "AsyncSocket");
