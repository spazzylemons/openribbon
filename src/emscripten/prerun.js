class ResourceManager {
    constructor() {
        this.slots = [];
    }

    open(value) {
        for (let i = 0; i < this.slots.length; i++) {
            if (!(i in this.slots)) {
                this.slots[i] = value;
                return i;
            }
        }
        this.slots.push(value);
        return this.slots.length - 1;
    }

    close(handle) {
        // TODO resize on more slots available
        delete this.slots[handle];
    }
}
