// Probably miserable binary serialization, but it works

const std = @import("std");

pub fn serialize(comptime T: type, serializable: *const T, alloc: *const std.mem.Allocator) ![]const u8 {
    const total_size = comptime serialized_size(T);
    const buffer = try alloc.alloc(u8, total_size + @sizeOf(u32));

    std.mem.writeInt(u32, buffer[0..@sizeOf(u32)], total_size, std.builtin.Endian.little);

    const sorted_fields = comptime blk: {
        const fields: []const std.builtin.Type.StructField = std.meta.fields(T);
        break :blk sort_fields(fields);
    };

    var i: u64 = @sizeOf(u32);
    inline for (sorted_fields) |state_field| {
        if (state_field.type == *const std.mem.Allocator) {
            continue;
        }

        const bytes = blk: {
            switch (@typeInfo(state_field.type)) {
                .Int => {
                    const bytes = try alloc.alloc(u8, @sizeOf(state_field.type));
                    const value = @field(serializable, state_field.name);
                    std.mem.writeInt(@TypeOf(value), bytes[0..4], value, std.builtin.Endian.little);

                    break :blk bytes;
                },
                else => @compileError(std.fmt.comptimePrint("Unsupported serialization type: {s}", .{@typeName(state_field.type)})),
            }
        };
        defer alloc.free(bytes);

        std.mem.copyForwards(u8, buffer[i..], bytes);
        i += bytes.len;
    }

    return buffer;
}

pub fn deserialize(comptime T: type, buffer: []const u8) !T {
    var obj: T = undefined;

    const sorted_fields = comptime blk: {
        const fields: []const std.builtin.Type.StructField = std.meta.fields(T);
        break :blk sort_fields(fields);
    };

    var i: u64 = 0;
    inline for (sorted_fields) |state_field| {
        if (state_field.type == *const std.mem.Allocator) {
            continue;
        }

        const field_bytes = buffer[i .. i + @sizeOf(state_field.type)];

        switch (@typeInfo(state_field.type)) {
            .Int => {
                const value = std.mem.readInt(state_field.type, field_bytes[0..@sizeOf(state_field.type)], std.builtin.Endian.little);
                @field(obj, state_field.name) = value;
            },
            else => @compileError(std.fmt.comptimePrint("Unsupported serialization type: {s}", .{@typeName(state_field.type)})),
        }

        i += @sizeOf(state_field.type);
    }

    return obj;
}

fn sort_fields(comptime fields: []const std.builtin.Type.StructField) []const std.builtin.Type.StructField {
    var sortable_fields: [fields.len]std.builtin.Type.StructField = undefined;
    std.mem.copyForwards(std.builtin.Type.StructField, &sortable_fields, fields);
    std.sort.pdq(std.builtin.Type.StructField, &sortable_fields, .{}, less_than);

    return &sortable_fields;
}

fn less_than(context: anytype, comptime lhs: std.builtin.Type.StructField, comptime rhs: std.builtin.Type.StructField) bool {
    _ = context;
    return switch (strcmp(lhs.name, rhs.name)) {
        .lt => true,
        else => false,
    };
}

fn serialized_size(comptime T: type) u32 {
    var total_size: u32 = 0;

    inline for (std.meta.fields(T)) |state_field| {
        if (state_field.type != *const std.mem.Allocator) {
            total_size += @sizeOf(state_field.type);
        }
    }

    return total_size;
}

pub inline fn strcmp(s1: [*c]const u8, s2: [*c]const u8) std.math.Order {
    return std.mem.orderZ(u8, s1, s2);
}
