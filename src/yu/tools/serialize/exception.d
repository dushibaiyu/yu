module yu.tools.serialize.exception;

import yu.exception;

mixin ExceptionBuild!("Serialize");

mixin ExceptionBuild!("Write","Serialize");

mixin ExceptionBuild!("Read","Serialize");