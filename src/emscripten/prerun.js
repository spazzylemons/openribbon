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

// Queue of pressed keys and when they were pressed.
const pressedQueue = [];

// listen for when keys are pressed
document.addEventListener('keydown', e => {
    const code = keyIds[e.code];
    if (code == undefined) return;
    pressedQueue.push({ id: code, time: e.timeStamp - eventEpoch });
    e.preventDefault();
});

// handles for audio tracks
const audioHandles = resourceManager();
// handles for resource requests
const requestHandles = resourceManager();
// audio context constructor, if available
const MyAudioContext = window.AudioContext || window.webkitAudioContext;
if (!MyAudioContext) throw 'AudioContext API is not supported by your browser';
// audio context for playing audio
const audioCtx = new MyAudioContext();
