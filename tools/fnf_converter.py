# converts fnf json files for quick and dirty tracks for testing

from math import inf
import json

with open('fresh.json') as file:
    fnf = json.load(file)
print(fnf)

with open('fresh.oron', 'w') as file:
    file.write('bpm={}\n'.format(float(fnf['bpm'])))

    used_times = set()
    obstacles = []

    for section in fnf['notes']:
        for note in section['sectionNotes']:
            if note[0] not in used_times:
                obstacles.append({
                    'time': note[0],
                    'type': ('b', 'p', 'l', 'w')[note[1] % 4],
                })
                used_times.add(note[0])
    obstacles.sort(key=lambda a: a['time'])

    minimum_space = 60000 / fnf['bpm']
    last_time = -inf
    for obstacle in obstacles:
        if obstacle['time'] - last_time >= minimum_space:
            file.write('obstacle[time={} type="{}"]\n'.format(obstacle['time'], obstacle['type']))
            last_time = obstacle['time']