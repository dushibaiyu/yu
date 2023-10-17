module yu.utils.serialize.exception;

import yu.exception;

mixin ExceptionBuild!("Serialize");

mixin ExceptionBuild!("Write","Serialize");

mixin ExceptionBuild!("Read","Serialize");
