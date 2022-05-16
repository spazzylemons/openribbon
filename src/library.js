mergeInto(LibraryManager.library, {
    jsLogImpl: function(level, scope, message) {
        level = UTF8ToString(level);
        scope = scope ? ('(' + UTF8ToString(scope) + ') ') : '';
        message = UTF8ToString(message);
        console[level](scope + message);
    },

    jsPanicImpl: function(ptr, len) {
        throw 'panic: ' + UTF8ToString(ptr, len);
    }
});
