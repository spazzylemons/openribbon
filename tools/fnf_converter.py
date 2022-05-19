# converts fnf json files for quick and dirty tracks for testing

import json

with open('fresh.json') as file:
    fnf = json.load(file)
print(fnf)

result = {'obstacles': []}

used_times = set()

for section in fnf['notes']:
    for note in section['sectionNotes']:
        if note[0] not in used_times:
            result['obstacles'].append({
                'time': note[0],
                'type': ('Block', 'Pit', 'Loop', 'Wave')[note[1] % 4],
            })
            used_times.add(note[0])

with open('new_fresh.json', 'w') as file:
    json.dump(result, file, indent=2)
