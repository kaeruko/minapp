(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  } else {
    root.MinAppNovelFormat = api;
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const FORMAT = 'minapp/novel@1';
  const ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
  const IMAGE_MIMES = new Set(['image/png', 'image/jpeg', 'image/webp', 'image/gif']);
  const AUDIO_MIMES = new Set(['audio/mpeg', 'audio/mp4', 'audio/ogg', 'audio/wav']);
  const EVENT_TYPES = new Set(['background', 'character', 'dialogue', 'choice', 'goto', 'bgm', 'se', 'end']);
  const SLOTS = new Set(['left', 'center', 'right']);

  class NovelFormatError extends Error {
    constructor(code, path, message) {
      super(`${code} at ${path}: ${message}`);
      this.name = 'NovelFormatError';
      this.code = code;
      this.path = path;
    }
  }

  function fail(code, path, message) {
    throw new NovelFormatError(code, path, message);
  }

  function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  function requireObject(value, path) {
    if (!isObject(value)) fail('invalid_type', path, 'expected object');
    return value;
  }

  function requireArray(value, path) {
    if (!Array.isArray(value)) fail('invalid_type', path, 'expected array');
    return value;
  }

  function requireString(value, path, options) {
    const opts = options || {};
    if (typeof value !== 'string') fail('invalid_type', path, 'expected string');
    if (opts.nonEmpty && value.length === 0) fail('invalid_value', path, 'must not be empty');
    if (opts.maxLength && value.length > opts.maxLength) fail('limit_exceeded', path, `maximum length is ${opts.maxLength}`);
    return value;
  }

  function requireId(value, path) {
    requireString(value, path, { nonEmpty: true, maxLength: 64 });
    if (!ID_RE.test(value)) fail('invalid_id', path, 'must match /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/');
    return value;
  }

  function requireExactKeys(object, allowedKeys, requiredKeys, path) {
    const allowed = new Set(allowedKeys);
    for (const key of Object.keys(object)) {
      if (!allowed.has(key)) fail('unknown_field', `${path}.${key}`, 'field is not part of minapp/novel@1');
    }
    for (const key of requiredKeys) {
      if (!Object.prototype.hasOwnProperty.call(object, key)) fail('missing_field', `${path}.${key}`, 'required field is missing');
    }
  }

  function validateRelativeAssetPath(src, path) {
    requireString(src, path, { nonEmpty: true, maxLength: 240 });
    if (src.startsWith('/') || src.includes('\\') || src.includes('?') || src.includes('#') || src.includes(':')) {
      fail('unsafe_asset_path', path, 'asset src must be a relative path without backslashes, URL schemes, query strings, or fragments');
    }
    const parts = src.split('/');
    if (parts.some((part) => part === '' || part === '.' || part === '..')) {
      fail('unsafe_asset_path', path, 'asset src contains an empty, dot, or parent segment');
    }
  }

  function validateAssets(story) {
    const assets = requireObject(story.assets, '$.assets');
    for (const [assetId, rawAsset] of Object.entries(assets)) {
      requireId(assetId, `$.assets.${assetId}`);
      const path = `$.assets.${assetId}`;
      const asset = requireObject(rawAsset, path);
      requireExactKeys(asset, ['kind', 'src', 'mime', 'alt'], ['kind', 'src'], path);
      if (asset.kind !== 'image' && asset.kind !== 'audio') fail('invalid_value', `${path}.kind`, 'must be image or audio');
      validateRelativeAssetPath(asset.src, `${path}.src`);
      if (Object.prototype.hasOwnProperty.call(asset, 'mime')) {
        requireString(asset.mime, `${path}.mime`, { nonEmpty: true });
        const allowed = asset.kind === 'image' ? IMAGE_MIMES : AUDIO_MIMES;
        if (!allowed.has(asset.mime)) fail('unsupported_mime', `${path}.mime`, `unsupported ${asset.kind} MIME type`);
      }
      if (Object.prototype.hasOwnProperty.call(asset, 'alt')) requireString(asset.alt, `${path}.alt`, { maxLength: 200 });
    }
    return assets;
  }

  function validateCharacters(story, assets) {
    const characters = requireObject(story.characters, '$.characters');
    for (const [characterId, rawCharacter] of Object.entries(characters)) {
      requireId(characterId, `$.characters.${characterId}`);
      const path = `$.characters.${characterId}`;
      const character = requireObject(rawCharacter, path);
      requireExactKeys(character, ['name', 'expressions'], ['name', 'expressions'], path);
      requireString(character.name, `${path}.name`, { nonEmpty: true, maxLength: 40 });
      const expressions = requireObject(character.expressions, `${path}.expressions`);
      if (Object.keys(expressions).length === 0) fail('invalid_value', `${path}.expressions`, 'at least one expression is required');
      for (const [expressionId, assetId] of Object.entries(expressions)) {
        requireId(expressionId, `${path}.expressions.${expressionId}`);
        requireId(assetId, `${path}.expressions.${expressionId}`);
        const asset = assets[assetId];
        if (!asset) fail('missing_asset', `${path}.expressions.${expressionId}`, `asset ${assetId} does not exist`);
        if (asset.kind !== 'image') fail('asset_kind_mismatch', `${path}.expressions.${expressionId}`, `asset ${assetId} is not an image`);
      }
    }
    return characters;
  }

  function requireAsset(assets, assetId, expectedKind, path) {
    requireId(assetId, path);
    const asset = assets[assetId];
    if (!asset) fail('missing_asset', path, `asset ${assetId} does not exist`);
    if (asset.kind !== expectedKind) fail('asset_kind_mismatch', path, `asset ${assetId} must be ${expectedKind}`);
    return asset;
  }

  function validateEvent(event, path, context) {
    requireObject(event, path);
    if (!Object.prototype.hasOwnProperty.call(event, 'id')) fail('missing_field', `${path}.id`, 'required field is missing');
    if (!Object.prototype.hasOwnProperty.call(event, 'type')) fail('missing_field', `${path}.type`, 'required field is missing');
    requireId(event.id, `${path}.id`);
    if (context.eventIds.has(event.id)) fail('duplicate_event_id', `${path}.id`, `event id ${event.id} is duplicated`);
    context.eventIds.add(event.id);
    requireString(event.type, `${path}.type`, { nonEmpty: true });
    if (!EVENT_TYPES.has(event.type)) fail('unknown_event_type', `${path}.type`, `unsupported event type ${event.type}`);

    switch (event.type) {
      case 'background':
        requireExactKeys(event, ['id', 'type', 'asset'], ['id', 'type', 'asset'], path);
        requireAsset(context.assets, event.asset, 'image', `${path}.asset`);
        return;
      case 'character': {
        requireExactKeys(event, ['id', 'type', 'action', 'slot', 'character', 'expression'], ['id', 'type', 'action', 'slot'], path);
        if (event.action !== 'show' && event.action !== 'hide') fail('invalid_value', `${path}.action`, 'must be show or hide');
        if (!SLOTS.has(event.slot)) fail('invalid_value', `${path}.slot`, 'must be left, center, or right');
        if (event.action === 'hide') {
          if (Object.prototype.hasOwnProperty.call(event, 'character') || Object.prototype.hasOwnProperty.call(event, 'expression')) {
            fail('invalid_field_combination', path, 'character hide must not include character or expression');
          }
          return;
        }
        if (!Object.prototype.hasOwnProperty.call(event, 'character')) fail('missing_field', `${path}.character`, 'show requires character');
        if (!Object.prototype.hasOwnProperty.call(event, 'expression')) fail('missing_field', `${path}.expression`, 'show requires expression');
        requireId(event.character, `${path}.character`);
        requireId(event.expression, `${path}.expression`);
        const character = context.characters[event.character];
        if (!character) fail('missing_character', `${path}.character`, `character ${event.character} does not exist`);
        if (!Object.prototype.hasOwnProperty.call(character.expressions, event.expression)) {
          fail('missing_expression', `${path}.expression`, `expression ${event.expression} does not exist on ${event.character}`);
        }
        return;
      }
      case 'dialogue':
        requireExactKeys(event, ['id', 'type', 'speaker', 'text'], ['id', 'type', 'text'], path);
        requireString(event.text, `${path}.text`, { nonEmpty: true, maxLength: 4000 });
        if (Object.prototype.hasOwnProperty.call(event, 'speaker')) {
          requireId(event.speaker, `${path}.speaker`);
          if (!context.characters[event.speaker]) fail('missing_character', `${path}.speaker`, `character ${event.speaker} does not exist`);
        }
        return;
      case 'choice': {
        requireExactKeys(event, ['id', 'type', 'options'], ['id', 'type', 'options'], path);
        const options = requireArray(event.options, `${path}.options`);
        if (options.length === 0) fail('invalid_value', `${path}.options`, 'at least one option is required');
        const optionIds = new Set();
        options.forEach((rawOption, index) => {
          const optionPath = `${path}.options[${index}]`;
          const option = requireObject(rawOption, optionPath);
          requireExactKeys(option, ['id', 'label', 'goto'], ['id', 'label', 'goto'], optionPath);
          requireId(option.id, `${optionPath}.id`);
          if (optionIds.has(option.id)) fail('duplicate_choice_id', `${optionPath}.id`, `choice id ${option.id} is duplicated in this event`);
          optionIds.add(option.id);
          requireString(option.label, `${optionPath}.label`, { nonEmpty: true, maxLength: 200 });
          requireId(option.goto, `${optionPath}.goto`);
          context.gotos.push({ path: `${optionPath}.goto`, target: option.goto });
        });
        return;
      }
      case 'goto':
        requireExactKeys(event, ['id', 'type', 'goto'], ['id', 'type', 'goto'], path);
        requireId(event.goto, `${path}.goto`);
        context.gotos.push({ path: `${path}.goto`, target: event.goto });
        return;
      case 'bgm':
        requireExactKeys(event, ['id', 'type', 'action', 'asset', 'loop'], ['id', 'type', 'action'], path);
        if (event.action !== 'play' && event.action !== 'stop') fail('invalid_value', `${path}.action`, 'must be play or stop');
        if (event.action === 'stop') {
          if (Object.prototype.hasOwnProperty.call(event, 'asset') || Object.prototype.hasOwnProperty.call(event, 'loop')) {
            fail('invalid_field_combination', path, 'bgm stop must not include asset or loop');
          }
          return;
        }
        if (!Object.prototype.hasOwnProperty.call(event, 'asset')) fail('missing_field', `${path}.asset`, 'bgm play requires asset');
        requireAsset(context.assets, event.asset, 'audio', `${path}.asset`);
        if (Object.prototype.hasOwnProperty.call(event, 'loop') && typeof event.loop !== 'boolean') fail('invalid_type', `${path}.loop`, 'expected boolean');
        return;
      case 'se':
        requireExactKeys(event, ['id', 'type', 'asset'], ['id', 'type', 'asset'], path);
        requireAsset(context.assets, event.asset, 'audio', `${path}.asset`);
        return;
      case 'end':
        requireExactKeys(event, ['id', 'type', 'label'], ['id', 'type'], path);
        if (Object.prototype.hasOwnProperty.call(event, 'label')) requireString(event.label, `${path}.label`, { maxLength: 100 });
        return;
      default:
        fail('unknown_event_type', `${path}.type`, `unsupported event type ${event.type}`);
    }
  }

  function validateStory(rawStory) {
    const story = requireObject(rawStory, '$');
    requireExactKeys(
      story,
      ['content_format', 'schema_version', 'content_revision', 'title', 'start_scene', 'assets', 'characters', 'scenes'],
      ['content_format', 'schema_version', 'content_revision', 'title', 'start_scene', 'assets', 'characters', 'scenes'],
      '$'
    );
    if (story.content_format !== FORMAT) fail('unsupported_format', '$.content_format', `expected ${FORMAT}`);
    if (story.schema_version !== 1) fail('unsupported_schema_version', '$.schema_version', 'expected 1');
    if (!Number.isInteger(story.content_revision) || story.content_revision < 1) fail('invalid_revision', '$.content_revision', 'must be an integer >= 1');
    requireString(story.title, '$.title', { nonEmpty: true, maxLength: 100 });
    requireId(story.start_scene, '$.start_scene');

    const assets = validateAssets(story);
    const characters = validateCharacters(story, assets);
    const scenes = requireObject(story.scenes, '$.scenes');
    if (Object.keys(scenes).length === 0) fail('invalid_value', '$.scenes', 'at least one scene is required');

    const context = { assets, characters, eventIds: new Set(), gotos: [] };
    for (const [sceneId, rawScene] of Object.entries(scenes)) {
      requireId(sceneId, `$.scenes.${sceneId}`);
      const path = `$.scenes.${sceneId}`;
      const scene = requireObject(rawScene, path);
      requireExactKeys(scene, ['id', 'events'], ['id', 'events'], path);
      requireId(scene.id, `${path}.id`);
      if (scene.id !== sceneId) fail('scene_id_mismatch', `${path}.id`, `scene key ${sceneId} must equal scene.id ${scene.id}`);
      const events = requireArray(scene.events, `${path}.events`);
      if (events.length === 0) fail('invalid_value', `${path}.events`, 'at least one event is required');
      events.forEach((event, index) => validateEvent(event, `${path}.events[${index}]`, context));
      const lastType = events[events.length - 1].type;
      if (lastType !== 'choice' && lastType !== 'goto' && lastType !== 'end') {
        fail('unterminated_scene', `${path}.events`, 'last event must be choice, goto, or end');
      }
    }

    if (!scenes[story.start_scene]) fail('missing_scene', '$.start_scene', `scene ${story.start_scene} does not exist`);
    for (const item of context.gotos) {
      if (!scenes[item.target]) fail('missing_scene', item.path, `scene ${item.target} does not exist`);
    }
    return story;
  }

  return {
    FORMAT,
    NovelFormatError,
    validateStory,
  };
});
