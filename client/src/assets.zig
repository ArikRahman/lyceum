const config = @import("config.zig");
const map = @import("components/hud/map.zig");
const messages = @import("server/messages.zig");
const rl = @import("raylib");
const std = @import("std");
const GameState = @import("game/state.zig");

const base_filepath = "./assets/";

fn load(
    comptime T: type,
    comptime err: anyerror,
    comptime whitelist: anytype,
    file_path: [:0]const u8,
) !T {
    const valid_extensions = comptime std.StaticStringMap(void).initComptime(whitelist);
    const extension = std.fs.path.extension(file_path);
    if (!valid_extensions.has(extension)) return err;

    const allocator = std.heap.c_allocator;
    const full_path = try std.fs.path.joinZ(allocator, &.{ base_filepath, file_path });
    defer allocator.free(full_path);

    return T.init(full_path);
}

pub fn image(imageFilePath: [:0]const u8) !rl.Image {
    return load(
        rl.Image,
        error.could_not_load_image,
        .{ .{".png"}, .{".jpg"} },
        imageFilePath,
    );
}

pub fn model(modelFilePath: [:0]const u8) !rl.Model {
    return load(
        rl.Model,
        error.could_not_load_model,
        .{ .{".glb"}, .{".obj"}, .{".m3d"} },
        modelFilePath,
    );
}

pub fn texture(textureFilePath: [:0]const u8) !rl.Texture {
    return load(
        rl.Texture,
        error.could_not_load_texture,
        .{ .{".png"}, .{".jpg"} },
        textureFilePath,
    );
}

pub fn animations(animationFilePath: [:0]const u8) ![]rl.ModelAnimation {
    // TODO: figure out the lack of init for this return type
    const allocator: std.mem.Allocator = std.heap.c_allocator;
    const fullFilePath = try std.fs.path.joinZ(allocator, &.{ base_filepath, animationFilePath });
    defer allocator.free(fullFilePath);
    const valid_extensions = comptime std.StaticStringMap(void).initComptime(.{.{".m3d"}});
    const extension = std.fs.path.extension(fullFilePath);
    if (!valid_extensions.has(extension)) {
        std.debug.print("Error trying to load animation model: .{s}", .{fullFilePath});
        return error.could_not_load_animation;
    }
    return try rl.loadModelAnimations(fullFilePath);
}

fn resizeImage(imageFilePath: [:0]const u8) !rl.Image {
    var img = try image(imageFilePath);
    rl.imageResize(&img, config.assets.tile.size, config.assets.tile.size);
    return img;
}

fn loadTile(kind: messages.Tile) !struct { ?rl.Model, ?rl.Image } {
    return switch (kind) {
        .dirt => .{ try model("tiles/dirt/dirt.obj"), try resizeImage("tiles/dirt/dirt.png") },
        .grass => .{ try model("tiles/grass/grass.obj"), try resizeImage("tiles/grass/grass.png") },
        .sand => .{ try model("tiles/sand/sand.obj"), try resizeImage("tiles/sand/sand.png") },
        .water => .{ try model("tiles/water/water.obj"), try resizeImage("tiles/water/water.png") },
        .empty => unreachable,
    };
}

pub fn tilesTable() !GameState.Tile_Table {
    var initTable = GameState.Tile_Table.initFull(.{ null, null });
    inline for (@typeInfo(messages.Tile).Enum.fields) |field| {
        if (!std.mem.eql(u8, field.name, "empty")) {
            const key: messages.Tile = @enumFromInt(field.value);
            const assets = try loadTile(key);
            initTable.put(key, assets);
        }
    }
    return initTable;
}

fn loadObject(kind: messages.Object) !rl.Model {
    return switch (kind) {
        .bush, .tree, .chest => try model("knight.glb"),
        .empty => unreachable,
    };
}

pub fn objectsTable() !GameState.Object_Table {
    var initTable = GameState.Object_Table.initFull(null);
    inline for (@typeInfo(messages.Object).Enum.fields) |field| {
        if (!std.mem.eql(u8, field.name, "empty")) {
            const key: messages.Object = @enumFromInt(field.value);
            const asset = try loadObject(key);
            initTable.put(key, asset);
        }
    }
    return initTable;
}

const tileRec: rl.Rectangle = .{
    .x = 0,
    .y = 0,
    .width = config.assets.tile.size,
    .height = config.assets.tile.size,
};

pub fn createMapImage(world: *const GameState.World.Map) !rl.Image {
    const width = world.instance.width;
    const height = world.instance.height;
    const tiles = world.instance.tiles;
    const iWidth: i32 = @intCast(width);
    const iHeight: i32 = @intCast(height);
    var img = rl.genImageColor(iWidth, iHeight, rl.Color.white);

    for (0..height) |i| {
        for (0..width) |j| {
            const tile = tiles[width * j + i];
            if (tile != .empty) {
                if (world.tiles.get(tile)) |tileData| {
                    _, const reducedTileImg = tileData;
                    const imgRec: rl.Rectangle = .{
                        .x = @floatFromInt(j * config.assets.tile.size),
                        .y = @floatFromInt(i * config.assets.tile.size),
                        .width = @floatFromInt(width),
                        .height = @floatFromInt(height),
                    };
                    rl.imageDraw(&img, reducedTileImg.?, tileRec, imgRec, rl.Color.white);
                } else {
                    std.debug.print("[ERROR] Tile kind not present in asset pool: .{}\n", .{tile});
                    return error.tile_kind_not_found;
                }
            }
        }
    }
    map.add_borders(&img);
    return img;
}
