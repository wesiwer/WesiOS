import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {resolveStagedAttachment, STAGED_UPLOAD_MIME} from './staged-upload.mjs';

const execFileAsync = promisify(execFile);

export const MAX_ATTACHMENTS = 4;
export const MAX_ATTACHMENT_BYTES = 15 * 1024 * 1024;
export const MAX_TOTAL_ATTACHMENT_BYTES = 18 * 1024 * 1024;
const MAX_EXTRACTED_FILES = 64;
const MAX_EXTRACTED_BYTES = 10 * 1024 * 1024;
const MAX_TEXT_CHARS_PER_FILE = 350000;
const MAX_TOTAL_TEXT_CHARS = 1400000;
const MAX_STAGED_TEXT_READ_BYTES = 2 * 1024 * 1024;
const MAX_GEMINI_PDF_BYTES = 50 * 1024 * 1024;

const TEXT_EXTENSIONS = new Set([
  'txt','md','markdown','csv','tsv','json','jsonl','xml','yaml','yml','html','htm','css',
  'js','mjs','cjs','ts','tsx','jsx','dart','py','java','kt','kts','swift','c','h','cc','cpp','hpp',
  'cs','go','rs','rb','php','sh','bash','zsh','fish','ps1','bat','cmd','sql','toml','ini','cfg','conf',
  'log','properties','gradle','lock','env','tex','rst','svg'
]);

const ARCHIVE_EXTENSIONS = new Set([
  'zip','7z','rar','tar','gz','tgz','bz2','tbz2','xz','txz','cab','iso','epub','apk','jar'
]);
const OFFICE_EXTENSIONS = new Set(['docx','xlsx','pptx','odt','ods','odp']);
const NATIVE_INLINE_PREFIXES = ['image/','audio/','video/'];
const NATIVE_INLINE_MIME = new Set(['application/pdf']);

function extensionOf(name) {
  const base = String(name || '').toLowerCase();
  const idx = base.lastIndexOf('.');
  return idx >= 0 ? base.slice(idx + 1) : '';
}

function safeName(raw) {
  const cleaned = String(raw || 'file')
    .replace(/[\\/\0-\x1f\x7f]/g, '_')
    .trim();
  return (cleaned || 'file').slice(-180);
}

function decodeBase64Strict(raw) {
  const value = String(raw || '').trim();
  if (!value || !/^[A-Za-z0-9+/]*={0,2}$/.test(value) || value.length % 4 !== 0) {
    throw new Error('WAI_ATTACHMENT_BAD_BASE64');
  }
  const bytes = Buffer.from(value, 'base64');
  const canonical = bytes.toString('base64').replace(/=+$/, '');
  if (canonical !== value.replace(/=+$/, '')) throw new Error('WAI_ATTACHMENT_BAD_BASE64');
  return bytes;
}

export function sanitizeAttachments(raw) {
  if (raw == null) return [];
  if (!Array.isArray(raw) || raw.length > MAX_ATTACHMENTS) throw new Error('WAI_ATTACHMENT_COUNT');
  let total = 0;
  const result = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object') throw new Error('WAI_ATTACHMENT_INVALID');
    const name = safeName(item.name);
    const mimeType = String(item.mimeType || 'application/octet-stream').trim().toLowerCase().slice(0, 120);
    const bytes = decodeBase64Strict(item.dataBase64);
    if (!bytes.length || bytes.length > MAX_ATTACHMENT_BYTES) throw new Error('WAI_ATTACHMENT_TOO_LARGE');
    const declared = Number(item.byteSize || 0);
    if (declared && declared !== bytes.length) throw new Error('WAI_ATTACHMENT_SIZE_MISMATCH');
    total += bytes.length;
    if (total > MAX_TOTAL_ATTACHMENT_BYTES) throw new Error('WAI_ATTACHMENTS_TOO_LARGE');
    result.push({name, mimeType, bytes, byteSize: bytes.length, extension: extensionOf(name)});
  }
  return result;
}

function isNativeProviderFile(item) {
  return NATIVE_INLINE_MIME.has(item.mimeType) || NATIVE_INLINE_PREFIXES.some((prefix) => item.mimeType.startsWith(prefix));
}

function mostlyText(bytes) {
  const sample = bytes.subarray(0, Math.min(bytes.length, 65536));
  if (!sample.length) return true;
  let printable = 0;
  for (const value of sample) {
    if (value === 9 || value === 10 || value === 13 || (value >= 32 && value < 127) || value >= 160) printable++;
  }
  return printable / sample.length >= 0.82;
}

function decodeText(bytes) {
  let text = bytes.toString('utf8').replace(/\u0000/g, '');
  text = text.replace(/\r\n/g, '\n');
  return text.slice(0, MAX_TEXT_CHARS_PER_FILE);
}

async function stagedPrefix(item, limit = MAX_STAGED_TEXT_READ_BYTES) {
  const handle = await fs.promises.open(item.filePath, 'r');
  try {
    const length = Math.min(item.byteSize, limit);
    const buffer = Buffer.alloc(length);
    const {bytesRead} = await handle.read(buffer, 0, length, 0);
    return buffer.subarray(0, bytesRead);
  } finally {
    await handle.close();
  }
}

function xmlToReadable(raw) {
  return raw
    .replace(/<w:tab\/?[^>]*>/gi, '\t')
    .replace(/<w:br\/?[^>]*>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/[ \t]+/g, ' ')
    .replace(/\n\s+/g, '\n')
    .trim();
}

async function walkFiles(root) {
  const found = [];
  let totalBytes = 0;
  async function walk(dir) {
    if (found.length >= MAX_EXTRACTED_FILES || totalBytes >= MAX_EXTRACTED_BYTES) return;
    const entries = await fs.promises.readdir(dir, {withFileTypes: true});
    for (const entry of entries) {
      if (found.length >= MAX_EXTRACTED_FILES || totalBytes >= MAX_EXTRACTED_BYTES) break;
      const full = path.join(dir, entry.name);
      const stat = await fs.promises.lstat(full);
      if (stat.isSymbolicLink()) continue;
      if (stat.isDirectory()) {
        await walk(full);
        continue;
      }
      if (!stat.isFile()) continue;
      totalBytes += stat.size;
      if (totalBytes > MAX_EXTRACTED_BYTES) break;
      found.push({full, relative: path.relative(root, full), size: stat.size});
    }
  }
  await walk(root);
  return found;
}

async function extractContainer(item) {
  const tempRoot = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'wesi-ai-att-'));
  const outputDir = path.join(tempRoot, 'out');
  await fs.promises.mkdir(outputDir, {recursive: true});
  let inputPath = item.filePath;
  if (!inputPath) {
    inputPath = path.join(tempRoot, safeName(item.name));
    await fs.promises.writeFile(inputPath, item.bytes, {mode: 0o600});
  }
  try {
    await execFileAsync('7z', ['x', '-y', '-bd', `-o${outputDir}`, inputPath], {
      timeout: 30000,
      maxBuffer: 1024 * 1024,
    });
    const files = await walkFiles(outputDir);
    const names = files.map((file) => file.relative).slice(0, MAX_EXTRACTED_FILES);
    let chars = 0;
    const sections = [`Содержимое контейнера ${item.name}:`, names.map((name) => `- ${name}`).join('\n')];
    for (const file of files) {
      if (chars >= MAX_TOTAL_TEXT_CHARS) break;
      const ext = extensionOf(file.relative);
      if (file.size > 2 * 1024 * 1024) continue;
      const bytes = await fs.promises.readFile(file.full);
      const textCandidate = TEXT_EXTENSIONS.has(ext) || ext === 'xml' || ext === 'rels' || mostlyText(bytes);
      if (!textCandidate) continue;
      let text = decodeText(bytes);
      if (ext === 'xml' || OFFICE_EXTENSIONS.has(item.extension)) text = xmlToReadable(text);
      if (!text.trim()) continue;
      const remaining = MAX_TOTAL_TEXT_CHARS - chars;
      text = text.slice(0, remaining);
      chars += text.length;
      sections.push(`\n--- ${file.relative} ---\n${text}`);
    }
    return sections.join('\n').slice(0, MAX_TOTAL_TEXT_CHARS);
  } catch {
    return `Не удалось полностью распаковать ${item.name}. Формат принят, но extractor вернул ошибку. Файл: ${item.name}, MIME: ${item.mimeType}, размер: ${item.byteSize} байт.`;
  } finally {
    await fs.promises.rm(tempRoot, {recursive: true, force: true});
  }
}

async function genericBinarySummary(item) {
  const bytes = item.filePath ? await stagedPrefix(item, 65536) : item.bytes;
  const hex = bytes.subarray(0, 64).toString('hex');
  const printable = mostlyText(bytes) ? decodeText(bytes) : '';
  if (printable.trim()) {
    return `Файл ${item.name} (${item.mimeType}, ${item.byteSize} байт):\n${printable}`;
  }
  return `Бинарный файл ${item.name}; MIME=${item.mimeType}; размер=${item.byteSize} байт; первые байты(hex)=${hex}. Если формат требует специального декодера, сообщи пользователю, что содержимое нельзя достоверно интерпретировать без него.`;
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function uploadGeminiFile(item, apiKey) {
  if (!apiKey) throw new Error('WAI_PROVIDER_NOT_CONFIGURED');
  if (!item.filePath) throw new Error('WAI_UPLOAD_REF_INVALID');
  if (item.mimeType === 'application/pdf' && item.byteSize > MAX_GEMINI_PDF_BYTES) {
    throw new Error('WAI_ATTACHMENT_PROVIDER_REJECTED');
  }
  const start = await fetch('https://generativelanguage.googleapis.com/upload/v1beta/files', {
    method: 'POST',
    headers: {
      'x-goog-api-key': apiKey,
      'X-Goog-Upload-Protocol': 'resumable',
      'X-Goog-Upload-Command': 'start',
      'X-Goog-Upload-Header-Content-Length': String(item.byteSize),
      'X-Goog-Upload-Header-Content-Type': item.mimeType,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({file: {display_name: item.name}}),
    signal: AbortSignal.timeout(30000),
  });
  if (!start.ok) throw new Error('WAI_ATTACHMENT_PROVIDER_REJECTED');
  const uploadUrl = start.headers.get('x-goog-upload-url');
  if (!uploadUrl || !/^https:\/\//.test(uploadUrl)) throw new Error('WAI_ATTACHMENT_PROVIDER_REJECTED');

  const upload = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      'Content-Length': String(item.byteSize),
      'Content-Type': item.mimeType,
      'X-Goog-Upload-Offset': '0',
      'X-Goog-Upload-Command': 'upload, finalize',
    },
    body: fs.createReadStream(item.filePath),
    duplex: 'half',
    signal: AbortSignal.timeout(300000),
  });
  let data = {};
  try { data = await upload.json(); } catch {}
  if (!upload.ok || !data?.file?.name) throw new Error('WAI_ATTACHMENT_PROVIDER_REJECTED');
  let file = data.file;
  for (let attempt = 0; String(file.state || '').toUpperCase() === 'PROCESSING' && attempt < 90; attempt++) {
    await sleep(2000);
    const status = await fetch(`https://generativelanguage.googleapis.com/v1beta/${file.name}`, {
      headers: {'x-goog-api-key': apiKey},
      signal: AbortSignal.timeout(15000),
    });
    if (!status.ok) throw new Error('WAI_ATTACHMENT_PROVIDER_REJECTED');
    file = await status.json();
  }
  if (String(file.state || '').toUpperCase() === 'FAILED' || !file.uri) {
    throw new Error('WAI_ATTACHMENT_PROVIDER_REJECTED');
  }
  return file;
}

export async function deleteGeminiFiles(fileNames, apiKey) {
  if (!apiKey) return;
  for (const raw of Array.isArray(fileNames) ? fileNames : []) {
    const name = String(raw || '');
    if (!/^files\/[A-Za-z0-9._-]+$/.test(name)) continue;
    try {
      await fetch(`https://generativelanguage.googleapis.com/v1beta/${name}`, {
        method: 'DELETE',
        headers: {'x-goog-api-key': apiKey},
        signal: AbortSignal.timeout(15000),
      });
    } catch {}
  }
}

export async function prepareGeminiAttachments(raw, apiKey = '') {
  const inlineItems = sanitizeAttachments(raw);
  const parts = [];
  const descriptors = [];
  const providerFiles = [];
  for (const inlineItem of inlineItems) {
    const staged = inlineItem.mimeType === STAGED_UPLOAD_MIME ? resolveStagedAttachment(inlineItem) : null;
    const item = staged || inlineItem;
    descriptors.push({name: item.name, mimeType: item.mimeType, byteSize: item.byteSize});
    if (isNativeProviderFile(item)) {
      parts.push({text: `\n[WESI_AI_ATTACHMENT name=${JSON.stringify(item.name)} mime=${JSON.stringify(item.mimeType)} size=${item.byteSize}]`});
      if (item.filePath) {
        const providerFile = await uploadGeminiFile(item, apiKey);
        providerFiles.push(providerFile.name);
        parts.push({fileData: {mimeType: item.mimeType, fileUri: providerFile.uri}});
      } else {
        parts.push({inlineData: {mimeType: item.mimeType, data: item.bytes.toString('base64')}});
      }
      continue;
    }
    const sample = item.filePath ? await stagedPrefix(item) : item.bytes;
    if (TEXT_EXTENSIONS.has(item.extension) || item.mimeType.startsWith('text/') || mostlyText(sample)) {
      parts.push({text: `\n[WESI_AI_ATTACHMENT_TEXT ${item.name}]\n${decodeText(sample)}`});
      continue;
    }
    if (ARCHIVE_EXTENSIONS.has(item.extension) || OFFICE_EXTENSIONS.has(item.extension) || /zip|rar|7z|tar|gzip|bzip|xz|officedocument|opendocument|epub/.test(item.mimeType)) {
      parts.push({text: `\n[WESI_AI_ATTACHMENT_CONTAINER ${item.name}]\n${await extractContainer(item)}`});
      continue;
    }
    parts.push({text: `\n[WESI_AI_ATTACHMENT_BINARY ${item.name}]\n${await genericBinarySummary(item)}`});
  }
  return {parts, descriptors, providerFiles};
}
