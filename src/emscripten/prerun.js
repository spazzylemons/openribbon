// Resource manager object for objects with integer handles.
function resourceManager() {
    return {
        slots: [],

        open(value) {
            for (let i = 0; i < this.slots.length; i++) {
                if (!(i in this.slots)) {
                    this.slots[i] = value;
                    return i;
                }
            }
            this.slots.push(value);
            return this.slots.length - 1;
        },

        close(handle) {
            // TODO resize on more slots available
            delete this.slots[handle];
        },
    };
}

// Relative time offset for all Event.timeStamp values.
let eventEpoch;
// initialize the event epoch
document.addEventListener('epoch', function handler(e) {
    eventEpoch = e.timeStamp;
    document.removeEventListener('epoch', handler);
});
document.dispatchEvent(new Event('epoch'));
// Relative time for all Date.now() values.
const dateEpoch = Date.now();

// Mappings of keyboard keys to key id enum.
const keyIds = {
    'KeyA': 0,
    'KeyZ': 1,
    'Quote': 2,
    'Slash': 3,
    'Space': 4,
};

// Set of all currently pressed keys.
const keysDown = {};

// Queue of pressed keys and when they were pressed.
const pressedQueue = [];

// listen for when keys are pressed
document.addEventListener('keydown', e => {
    const code = keyIds[e.code];
    if (code == undefined) return;
    keysDown[code] = 0;
    pressedQueue.push({ id: code, time: e.timeStamp - eventEpoch });
    e.preventDefault();
});

// listen for when keys are released
document.addEventListener('keyup', e => {
    const code = keyIds[e.code];
    if (code == undefined) return;
    delete keysDown[code];
    e.preventDefault();
});

// handles for audio tracks
const audioHandles = resourceManager();
// handles for resource requests
const requestHandles = resourceManager();
// audio context for playing audio
const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
