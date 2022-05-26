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

    jsNextPressedKey: function(idPtr, timePtr) {
        if (!pressedQueue.length) return 0;
        const result = pressedQueue.shift();
        Module['HEAPU8'][idPtr] = result.id;
        Module['HEAPU32'][timePtr >> 2] = result.time;
        return 1;
    },

    jsGetTicks: function() {
        return Date.now() - dateEpoch;
    },

    jsAudioOpen: function(src) {
        const audio = new Audio(UTF8ToString(src));
        const track = audioCtx.createMediaElementSource(audio);
        track.connect(audioCtx.destination);
        const handle = audioHandles.open({ ready: false, track, time: 0 });
        audio.load();
        audio.addEventListener('canplaythrough', () => {
            audioHandles.slots[handle].ready = true;
        });
        audio.addEventListener('timeupdate', () => {
            audioHandles.slots[handle].time = audio.currentTime * 1000;
        });
        return handle;
    },

    jsAudioReady: function(handle) {
        return audioHandles.slots[handle].ready;
    },

    jsAudioClose: function(handle) {
        audioHandles.slots[handle].track.mediaElement.pause();
        audioHandles.slots[handle].track.disconnect();
        audioHandles.close(handle);
    },

    jsAudioPlay: function(handle) {
        audioHandles.slots[handle].track.mediaElement.play();
    },

    jsAudioTell: function(handle) {
        return audioHandles.slots[handle].time;
    },

    jsAudioStat: function(handle) {
        const d = audioHandles.slots[handle].track.mediaElement.duration;
        // if the media is streaming, duration is Infinity
        if (d === Infinity) return -1;
        return d * 1000;
    },

    jsReqOpen: function(ptr) {
        const filename = UTF8ToString(ptr);
        const obj = { ready: false };
        const handle = requestHandles.open(obj);
        fetch(filename)
            .then(res => res.arrayBuffer())
            .then(buf => obj.value = buf)
            .catch(e => console.error(e))
            .finally(() => obj.ready = true);
        return handle;
    },

    jsReqReady: function(handle) {
        return requestHandles.slots[handle].ready;
    },

    jsReqError: function(handle) {
        return !requestHandles.slots[handle].value;
    },

    jsReqClose: function(handle) {
        requestHandles.close(handle);
    },

    jsReqStat: function(handle) {
        return requestHandles.slots[handle].value.byteLength;
    },

    jsReqRead: function(handle, dst) {
        const src = new Uint8Array(requestHandles.slots[handle].value);
        Module['HEAPU8'].set(src, dst);
    },

    jsParseFloat: function(ptr, len) {
        return +UTF8ToString(ptr, len);
    },
});
