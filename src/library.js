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

    jsGetAudioPos: function(handle) {
        // TODO on firefox this updates infrequently (works well on chromium)
        return openAudios[handle].currentTime * 1000;
    },

    jsGetAudioDuration: function(handle) {
        var d = openAudios[handle].duration;
        // if the media is streaming, duration is Infinity
        if (d == Infinity) return -1;
        return d * 1000;
    },

    jsMakeRequest: function(ptr) {
        var filename = UTF8ToString(ptr);
        var handle = requestId++;
        fetch(filename)
            .then(function(result) {
                return result.arrayBuffer();
            })
            .then(function (result) {
                readyRequests[handle] = result;
            })
            .catch(function (e) {
                console.error(e);
                readyRequests[handle] = null;
            });
    },

    jsGetRequestReady: function(handle) {
        return handle in readyRequests;
    },

    jsGetRequestFailed: function(handle) {
        return readyRequests[handle] == null;
    },

    jsCloseRequest: function(handle) {
        delete readyRequests[handle];
    },

    jsGetRequestSize: function(handle) {
        return readyRequests[handle].byteLength;
    },

    jsCopyRequestContent: function(handle, ptr) {
        Module.HEAPU8.set(new Uint8Array(readyRequests[handle]), ptr);
    },

    roundq: function(i) {
        return Math.round(i);
    },
});
