mergeInto(LibraryManager.library, {
    jsLogImpl: function(level, scope, message) {
        level = UTF8ToString(level);
        scope = scope ? ('(' + UTF8ToString(scope) + ') ') : '';
        message = UTF8ToString(message);
        console[level](scope + message);
    },

    jsPanicImpl: function(ptr, len) {
        throw 'panic: ' + UTF8ToString(ptr, len);
    },

    jsNewAudio: function(src) {
        try {
            var audio = new Audio(UTF8ToString(src));
            audio.load();
            var handle = audioId++;
            audio.addEventListener('canplaythrough', function(e) {
                readyAudios[handle] = true;
            });
            openAudios[handle] = audio;
            return handle;
        } catch (e) {
            console.error(e);
            return -1;
        }
    },

    jsIsAudioReady: function(handle) {
        if (readyAudios[handle]) {
            delete readyAudios[handle];
            return 1;
        }
        return 0;
    },

    jsFreeAudio: function(handle) {
        openAudios[handle].pause();
        delete openAudios[handle];
    },

    jsPlayAudio: function(handle) {
        openAudios[handle].play();
    },
});
