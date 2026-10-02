// 黑盒测试：MoomemError 的 message 与 kind。

///|
test "MoomemError: message and kind cover every variant" {
  let invalid = @src.MoomemError::InvalidUserId("empty")
  inspect(invalid.message(), content="invalid user_id: empty")
  inspect(invalid.kind(), content="invalid_user_id")
  let corrupted = @src.MoomemError::StoreCorrupted("bad header")
  inspect(corrupted.message(), content="store corrupted: bad header")
  inspect(corrupted.kind(), content="store_corrupted")
  let io = @src.MoomemError::IoFailure("disk")
  inspect(io.message(), content="io failure: disk")
  inspect(io.kind(), content="io_failure")
  let extraction = @src.MoomemError::ExtractionFailure("down")
  inspect(extraction.message(), content="extraction failure: down")
  inspect(extraction.kind(), content="extraction_failure")
  let embedding = @src.MoomemError::EmbeddingFailure("down")
  inspect(embedding.message(), content="embedding failure: down")
  inspect(embedding.kind(), content="embedding_failure")
  let backend = @src.MoomemError::BackendUnsupported("wasm")
  inspect(backend.message(), content="backend unsupported: wasm")
  inspect(backend.kind(), content="backend_unsupported")
  let operation = @src.MoomemError::InvalidOperation("closed")
  inspect(operation.message(), content="invalid operation: closed")
  inspect(operation.kind(), content="invalid_operation")
}
