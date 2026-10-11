function files_compat_error(error) {
  return io_fail(Math.abs(error?.errno ?? 5));
}

function files_compat_path(path) {
  const bytes = io_bytes(path);
  if (bytes.includes(0)) return { ok: false, code: 22 };
  return { ok: true, value: Buffer.from(bytes) };
}

function files_compat_read_words(file, max) {
  const size = Math.min(Number(max), 1048576);
  const buffer = Buffer.allocUnsafe(size);
  try {
    const count = require("fs").readSync(file, buffer, 0, size, null);
    const words = Array(Math.ceil(count / 4)).fill(0);
    for (let index = 0; index < count; index++) {
      words[index >> 2] = (words[index >> 2] |
        (buffer[index] << (8 * (index & 3)))) >>> 0;
    }
    return io_tup(file, io_done(io_tup(count, words)));
  } catch (error) {
    return io_tup(file, files_compat_error(error));
  }
}

function files_compat_write_words_once(file, offset, len, words) {
  const start = Number(offset);
  const size = Number(len);
  if (start + size > words.length * 4) return io_tup(file, io_fail(22));
  const bytes = Buffer.allocUnsafe(size);
  for (let index = 0; index < size; index++) {
    bytes[index] = (words[(start + index) >> 2] >>>
      (8 * ((start + index) & 3))) & 255;
  }
  try {
    const count = require("fs").writeSync(file, bytes, 0, size);
    return io_tup(file, io_done(io_tup(count, words)));
  } catch (error) {
    return io_tup(file, files_compat_error(error));
  }
}

function files_compat_stat(path) {
  const got = files_compat_path(path);
  if (!got.ok) return io_fail(got.code);
  try {
    const info = require("fs").statSync(got.value);
    const kind = info.isFile() ? 0 : info.isDirectory() ? 1 : 2;
    return io_done(io_tup(kind, info.size >>> 0,
      Math.floor(info.mtimeMs / 1000) >>> 0));
  } catch (error) {
    return files_compat_error(error);
  }
}

function files_compat_remove(path) {
  const got = files_compat_path(path);
  if (!got.ok) return io_fail(got.code);
  try {
    const fs = require("fs");
    if (fs.lstatSync(got.value).isDirectory()) fs.rmdirSync(got.value);
    else fs.unlinkSync(got.value);
    return io_done({ $: CID(Unit) });
  } catch (error) {
    return files_compat_error(error);
  }
}

function files_compat_rename(from, to) {
  const source = files_compat_path(from);
  const destination = files_compat_path(to);
  if (!source.ok) return io_fail(source.code);
  if (!destination.ok) return io_fail(destination.code);
  try {
    require("fs").renameSync(source.value, destination.value);
    return io_done({ $: CID(Unit) });
  } catch (error) {
    return files_compat_error(error);
  }
}

io_eff(CID(read.words), files_compat_read_words);
io_eff(CID(write.words.once), files_compat_write_words_once);
io_eff(CID(stat.raw), files_compat_stat);
io_eff(CID(remove), files_compat_remove);
io_eff(CID(rename), files_compat_rename);
