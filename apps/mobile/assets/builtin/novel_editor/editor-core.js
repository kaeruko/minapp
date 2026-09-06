(function (root, factory) {
  'use strict';
  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  } else {
    root.MinAppNovelEditorCore = api;
  }
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const FORMAT = 'minapp/novel@1';
  const PROJECT_FIELDS = new Set([
    'content_id',
    'group_id',
    'content_format',
    'status',
    'draft_revision',
    'assets',
    'created_at',
    'updated_at',
    'document',
  ]);
  const SAVE_RESPONSE_FIELDS = new Set([
    'content_id',
    'group_id',
    'content_format',
    'status',
    'draft_revision',
    'assets',
    'created_at',
    'updated_at',
  ]);
  const PUBLISH_RESPONSE_FIELDS = new Set([
    'content_id',
    'group_id',
    'content_format',
    'published_version',
    'source_revision',
    'assets',
    'published_at',
  ]);

  class NovelEditorContractError extends Error {
    constructor(code, message) {
      super(message);
      this.name = 'NovelEditorContractError';
      this.code = code;
    }
  }

  function fail(code, message) {
    throw new NovelEditorContractError(code, message);
  }

  function isObject(value) {
    return value !== null && typeof value === 'object' && !Array.isArray(value);
  }

  function requireExactFields(value, expected, context) {
    if (!isObject(value)) fail('invalid_authoring_response', `${context} must be an object`);
    const actual = Object.keys(value);
    if (actual.length !== expected.size || actual.some((key) => !expected.has(key))) {
      fail('invalid_authoring_response', `${context} fields do not match the Authoring contract`);
    }
  }

  function requirePositiveInteger(value, context) {
    if (!Number.isInteger(value) || value < 1) {
      fail('invalid_authoring_response', `${context} must be a positive integer`);
    }
    return value;
  }

  function requireString(value, context) {
    if (typeof value !== 'string' || value.length === 0) {
      fail('invalid_authoring_response', `${context} must be a non-empty string`);
    }
    return value;
  }

  function requireFormat(value) {
    if (value !== FORMAT) {
      fail('unsupported_content_format', `Editor requires exact ${FORMAT}`);
    }
  }

  function validateProject(payload, validateStory) {
    if (typeof validateStory !== 'function') {
      throw new TypeError('validateStory must be a function');
    }
    requireExactFields(payload, PROJECT_FIELDS, 'Authoring load response');
    requireString(payload.content_id, 'content_id');
    requireString(payload.group_id, 'group_id');
    requireFormat(payload.content_format);
    if (payload.status !== 'draft') {
      fail('content_not_editable', 'Authoring content status must be draft');
    }
    requirePositiveInteger(payload.draft_revision, 'draft_revision');
    if (!Array.isArray(payload.assets)) {
      fail('invalid_authoring_response', 'assets must be a list');
    }
    requireString(payload.created_at, 'created_at');
    requireString(payload.updated_at, 'updated_at');
    if (!isObject(payload.document)) {
      fail('invalid_authoring_response', 'document must be an object');
    }
    const document = validateStory(payload.document);
    return {
      contentId: payload.content_id,
      draftRevision: payload.draft_revision,
      document: deepClone(document),
      assets: deepClone(payload.assets),
    };
  }

  function prepareDocumentSave(document, validateStory) {
    if (typeof validateStory !== 'function') {
      throw new TypeError('validateStory must be a function');
    }
    if (!isObject(document)) {
      fail('invalid_editor_document', 'Editor document must be an object');
    }
    const next = deepClone(document);
    requireFormat(next.content_format);
    const currentContentRevision = requirePositiveInteger(
      next.content_revision,
      'document.content_revision',
    );
    next.content_revision = currentContentRevision + 1;
    return validateStory(next);
  }

  function validateSaveResponse(payload, expectedRevision, expectedContentId) {
    requirePositiveInteger(expectedRevision, 'expectedRevision');
    requireExactFields(payload, SAVE_RESPONSE_FIELDS, 'Authoring save response');
    requireFormat(payload.content_format);
    if (payload.content_id !== expectedContentId) {
      fail('authoring_scope_changed', 'Authoring save response changed content scope');
    }
    if (payload.status !== 'draft') {
      fail('content_not_editable', 'Saved Authoring content must remain draft');
    }
    if (payload.draft_revision !== expectedRevision + 1) {
      fail('authoring_revision_changed', 'Authoring save did not advance exactly one revision');
    }
    if (!Array.isArray(payload.assets)) {
      fail('invalid_authoring_response', 'assets must be a list');
    }
    return payload.draft_revision;
  }

  function validatePublishResponse(payload, expectedRevision, expectedContentId) {
    requirePositiveInteger(expectedRevision, 'expectedRevision');
    requireExactFields(payload, PUBLISH_RESPONSE_FIELDS, 'Authoring publish response');
    requireFormat(payload.content_format);
    if (payload.content_id !== expectedContentId) {
      fail('authoring_scope_changed', 'Authoring publish response changed content scope');
    }
    if (payload.source_revision !== expectedRevision) {
      fail('authoring_revision_changed', 'Published source revision does not match requested draft revision');
    }
    requirePositiveInteger(payload.published_version, 'published_version');
    if (!Array.isArray(payload.assets)) {
      fail('invalid_authoring_response', 'assets must be a list');
    }
    requireString(payload.published_at, 'published_at');
    return payload.published_version;
  }

  function deepClone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  return {
    FORMAT,
    NovelEditorContractError,
    validateProject,
    prepareDocumentSave,
    validateSaveResponse,
    validatePublishResponse,
    deepClone,
  };
});
