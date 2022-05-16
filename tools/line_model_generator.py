bl_info = {
    'name': 'Line Model Generator',
    'author': 'spazzylemons',
    'version': (1, 0, 0),
    'blender': (3, 1, 2),
    'location': 'File > Import-Export',
    'description': 'Generate Line Model',
    'category': 'Import-Export',
}

from typing import Iterable
import bpy

from bpy_extras.io_utils import (ExportHelper)
from struct import pack

from collections import deque

def conv_vector(v: tuple[float, float, float]) -> tuple[float, float, float]:
    x, y, z = v
    return x, z, y

class Graph:
    @staticmethod
    def _sort_pair(pair: tuple[int, int]) -> tuple[int, int]:
        if pair[1] < pair[0]:
            return pair[1], pair[0]
        return pair

    def __init__(self, size: int):
        self.adjacent = [[] for _ in range(size)]
        self.pairs = set()

    def add(self, pair: tuple[int, int]) -> None:
        pair = Graph._sort_pair(pair)
        if pair not in self.pairs:
            self.adjacent[pair[0]].append(pair[1])
            self.adjacent[pair[1]].append(pair[0])
            self.pairs.add(pair)

    def find_adjacent(self, v: int) -> tuple[int, ...]:
        return tuple(self.adjacent[v])

    def remove(self, pair: tuple[int, int]):
        pair = Graph._sort_pair(pair)
        if pair in self.pairs:
            self.adjacent[pair[0]].remove(pair[1])
            self.adjacent[pair[1]].remove(pair[0])
            self.pairs.remove(pair)

    def pop(self) -> tuple[int, int]:
        pair = self.pairs.pop()
        self.adjacent[pair[0]].remove(pair[1])
        self.adjacent[pair[1]].remove(pair[0])
        return pair

    def __iter__(self) -> Iterable[tuple[int, int]]:
        return iter(self.pairs)

    def __contains__(self, pair: tuple[int, int]) -> bool:
        return tuple(sorted(pair)) in self.pairs

    def __len__(self) -> int:
        return len(self.pairs)

def find_line_groups(graph: Graph) -> list[list[int]]:
    # TODO make this less greedy but keep efficiency
    groups = []
    while len(graph):
        pair = graph.pop()
        order = deque(pair)
        # go to the left
        u = pair[0]
        while adj := graph.find_adjacent(u):
            v = adj[0]
            graph.remove((u, v))
            order.appendleft(v)
            u = v
        # go to the right
        u = pair[1]
        while adj := graph.find_adjacent(u):
            v = adj[0]
            graph.remove((u, v))
            order.append(v)
            u = v
        groups.append(order)
    return groups

class GenerateModel(bpy.types.Operator, ExportHelper):
    """Export the selected mesh"""
    bl_idname = 'line_model_generator.generate_model'
    bl_label = 'Generate Line Model'

    filename_ext = '.bin'

    def execute(self, context):
        try:
            mesh = bpy.data.meshes[context.active_object.data.name]

            graph = Graph(len(mesh.vertices))
            for edge in mesh.edges:
                graph.add((edge.vertices[0], edge.vertices[1]))
            groups = find_line_groups(graph)

            with open(self.filepath, 'wb') as file:
                # vertices
                file.write(pack('>B', len(mesh.vertices)))
                for vertex in mesh.vertices:
                    file.write(pack('>hhh', *(round(v * 256) for v in conv_vector(vertex.co))))
                # groups
                file.write(pack('>B', len(groups)))
                for group in groups:
                    file.write(pack('>B', len(group) - 2))
                    for i in group:
                        file.write(pack('>B', i))
        except BaseException as e:
            self.report({'ERROR'}, repr(e))
            return {'CANCELLED'}
        else:
            return {'FINISHED'}

def generate_func(self, context):
    self.layout.operator(GenerateModel.bl_idname)

def register():
    bpy.utils.register_class(GenerateModel)
    bpy.types.TOPBAR_MT_file_export.append(generate_func)

def unregister():
    bpy.types.TOPBAR_MT_file_export.remove(generate_func)
    bpy.utils.unregister_class(GenerateModel)
