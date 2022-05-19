mergeInto(LibraryManager.library, {
    jsLog: function(level, scope, message) {
        level = UTF8ToString(level);
        scope = scope ? ('(' + UTF8ToString(scope) + ') ') : '';
        message = UTF8ToString(message);
        console[level](scope + message);
    },

    jsPanic: function(ptr, len) {
        throw 'panic: ' + UTF8ToString(ptr, len);
    },

    $audioLib: function() {
        const handles = new ResourceManager();

        _jsAudioOpen = function(src) {
            const audio = new Audio(UTF8ToString(src));
            const handle = handles.open({ ready: false, audio });
            audio.load();
            audio.addEventListener('canplaythrough', function(e) {
                handles.slots[handle].ready = true;
            });
            return handle;
        };

        _jsAudioReady = function(handle) {
            return handles.slots[handle].ready;
        };
    
        _jsAudioClose = function(handle) {
            handles.slots[handle].audio.pause();
            handles.close(handle);
        };
    
        _jsAudioPlay = function(handle) {
            // TODO - audio playback is delayed
            handles.slots[handle].audio.play();
        };
    
        _jsAudioTell = function(handle) {
            // TODO on firefox this updates infrequently (works well on chromium)
            return handles.slots[handle].audio.currentTime * 1000;
        };
    
        _jsAudioStat = function(handle) {
            const d = handles.slots[handle].audio.duration;
            // if the media is streaming, duration is Infinity
            if (d === Infinity) return -1;
            return d * 1000;
        };
    },
    $audioLib__postset: 'audioLib();',

    jsAudioOpen: function() {},
    jsAudioOpen__deps: ['$audioLib'],

    jsAudioReady: function() {},
    jsAudioReady__deps: ['$audioLib'],

    jsAudioClose: function() {},
    jsAudioClose__deps: ['$audioLib'],

    jsAudioPlay: function() {},
    jsAudioPlay__deps: ['$audioLib'],

    jsAudioTell: function() {},
    jsAudioTell__deps: ['$audioLib'],

    jsAudioStat: function() {},
    jsAudioStat__deps: ['$audioLib'],

    $requestLib: function() {
        const handles = new ResourceManager();

        _jsReqOpen = function(ptr) {
            const filename = UTF8ToString(ptr);
            const obj = { ready: false };
            const handle = handles.open(obj);
            fetch(filename)
                .then(res => res.arrayBuffer())
                .then(buf => obj.value = buf)
                .catch(e => console.error(e))
                .finally(() => obj.ready = true);
            return handle;
        };
    
        _jsReqReady = function(handle) {
            return handles.slots[handle].ready;
        };
    
        _jsReqError = function(handle) {
            return !handles.slots[handle].value;
        };
    
        _jsReqClose = handles.close.bind(handles);
    
        _jsReqStat = function(handle) {
            return handles.slots[handle].value.byteLength;
        };
    
        _jsReqRead = function(handle, dst) {
            const src = new Uint8Array(handles.slots[handle].value);
            Module.HEAPU8.set(src, dst);
        };
    },
    $requestLib__postset: 'requestLib();',

    jsReqOpen: function() {},
    jsReqOpen__deps: ['$requestLib'],

    jsReqReady: function() {},
    jsReqReady__deps: ['$requestLib'],

    jsReqError: function() {},
    jsReqError__deps: ['$requestLib'],

    jsReqClose: function() {},
    jsReqClose__deps: ['$requestLib'],

    jsReqStat: function() {},
    jsReqStat__deps: ['$requestLib'],

    jsReqRead: function() {},
    jsReqRead__deps: ['$requestLib'],

    roundq: function(i) {
        return Math.round(i);
    },
});
