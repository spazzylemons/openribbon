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

    jsInitWebGl: function(major, minor) {
        const canvas = Module['canvas'];
        const webgl = canvas.getContext('webgl', { antialias: false });
        if (!webgl) return -1;
        const ctx = GL.createContext(canvas, {
            majorVersion: major,
            minorVersion: minor,
        });
        GL.makeContextCurrent(ctx);
        return 0;
    },

    jsGetCanvasSize: function(width, height) {
        const canvas = Module['canvas'];
        Module['HEAP32'][width >> 2] = canvas.width;
        Module['HEAP32'][height >> 2] = canvas.height;
    },

    jsSetCanvasSize: function(width, height) {
        const canvas = Module['canvas'];
        canvas.width = width;
        canvas.height = height;
    },

    jsGetKeyDown: function() {
        const values = {
            'KeyA': 0,
            'KeyZ': 1,
            'Quote': 2,
            'Slash': 3,
            'Space': 4,
        };
        const down = {};

        document.addEventListener('keydown', e => {
            if (e.code in values) {
                console.log('down', e.code);
                down[values[e.code]] = 0;
                e.preventDefault();
            }
        });

        document.addEventListener('keyup', e => {
            if (e.code in values) {
                console.log('up', e.code);
                delete down[values[e.code]];
                e.preventDefault();
            }
        });

        _jsGetKeyDown = function(index) {
            return index in down;
        };
    },
    jsGetKeyDown__postset: '_jsGetKeyDown();',

    jsGetTicks: function() {
        const start = Date.now();

        _jsGetTicks = function() {
            return Date.now() - start;
        }
    },
    jsGetTicks__postset: '_jsGetTicks();',

    $audioLib: function() {
        const handles = new ResourceManager();
        const AudioContext = window.AudioContext || window.webkitAudioContext;
        const ctx = new AudioContext();

        _jsAudioOpen = function(src) {
            const audio = new Audio(UTF8ToString(src));
            const track = ctx.createMediaElementSource(audio);
            track.connect(ctx.destination);
            const handle = handles.open({ ready: false, track });
            audio.load();
            audio.addEventListener('canplaythrough', () => {
                handles.slots[handle].ready = true;
            });
            return handle;
        };

        _jsAudioReady = function(handle) {
            return handles.slots[handle].ready;
        };
    
        _jsAudioClose = function(handle) {
            handles.slots[handle].track.mediaElement.pause();
            handles.slots[handle].track.disconnect();
            handles.close(handle);
        };
    
        _jsAudioPlay = function(handle) {
            handles.slots[handle].track.mediaElement.play();
        };
    
        _jsAudioTell = function(handle) {
            // TODO on firefox this updates infrequently (works well on chromium)
            return handles.slots[handle].track.mediaElement.currentTime * 1000;
        };
    
        _jsAudioStat = function(handle) {
            const d = handles.slots[handle].track.mediaElement.duration;
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
            Module['HEAPU8'].set(src, dst);
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

    jsParseFloat: function(ptr, len) {
        return +UTF8ToString(ptr, len);
    },
});
