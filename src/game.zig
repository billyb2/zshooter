const std = @import("std");
const serde = @import("serialize.zig");

pub const State = struct {
    alloc: *const std.mem.Allocator,
    position: i32,

    pub fn update(self: *const State) !State {
        return State{
            .alloc = self.alloc,
            .position = self.position + 1,
        };
    }

    pub fn serialize(self: *const State, alloc: *const std.mem.Allocator) ![]const u8 {
        const data = try serde.serialize(State, self, alloc);
        std.debug.print("serialized state is {d} bytes\n", .{data.len});
        return data;
    }

    pub fn deserialize(data: []u8) !State {
        const state = try serde.deserialize(State, data);
        return state;
    }
};
