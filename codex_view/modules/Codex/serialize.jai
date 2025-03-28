
// @Copypasta from Sokoban. Maybe we should provide these in String_Builder now that
// it doesn't cost much due to DCE.

put :: (builder: *String_Builder, x: $T)
#modify {
    ti := cast(*Type_Info) T;
    if ti.type == .INTEGER return true;  // Accept integers.
    if ti.type == .FLOAT   return true;  // Accept floats.
    if ti.type == .BOOL    return true;  // Accept bools.
    if ti.type == .ENUM    return true;  // Accept enums.

    return false;                        // Reject anything else.
}
{
    ensure_contiguous_space(builder, size_of(T));

    if TARGET_IS_LITTLE_ENDIAN {  // Use #if here?
        simple_memcpy(builder, x);
    } else {
        // @Incomplete: Do a slow-path if we know we are not little-endian. This can be generated by #run_and_insert?
        assert(false);
    }
}

put :: (builder: *String_Builder, x: string) {
    if x.data == null {
        assert(x.count == 0);
    }
    
    put(builder, x.count);
    append(builder, x.data, x.count);
}


get :: (s: *string, x: *$T)
#modify {  // @Cutnpaste from put
    using Type_Info_Tag;

    ti := cast(*Type_Info) T;
    if ti.type == INTEGER return true;  // Accept integers.
    if ti.type == FLOAT   return true;  // Accept floats.
    if ti.type == BOOL    return true;  // Accept bools.
    if ti.type == ENUM    return true;  // Accept enums.

    return false;                      // Reject anything else.
}
{
    assert(s.count >= size_of(T));

    if TARGET_IS_LITTLE_ENDIAN {
        memcpy(x, s.data, size_of(T));
    } else {
        // @Incomplete: Do a slow-path if we know we are not little-endian. This can be generated by #run_and_insert?
        assert(false);
    }

    s.data  += size_of(T);
    s.count -= size_of(T);
}

get :: (s: *string, result: *string, error: *bool) { // Reads a full-sized string, allocating the result.
    count: s64;
    get(s, *count);

    if count < 0 {
        <<error = true;
        return;
    }
    
    result.data = alloc(count);
    if !result.data {
        <<error = true;
        return;
    }
    
    success := consume_u8_and_length(s, result.data, count);
    if !success {
        <<error = true;
        return;
    }
}

//
// Often we know we are packing strings that are pretty short, so here are some routines
// to help us do that easily. In your file format, you decide whether strings will have
// a count that is 1, 2, or 4 bytes, and call the appropriate routine here with
// count_type = u8, u16, or u32. The file format is that many bytes for the count, followed
// immediately by the string data.
//
put_short_string :: (builder: *String_Builder, s: string, $count_type: Type, $zero_terminated := false) {  // T must be u8, u16, or u32.
    T :: count_type;
    #assert((T == u8) || (T == u16) || (T == u32) || (T == s8) || (T == s16) || (T == s32));

    count := cast(T) s.count; // This will cast-bounds fail if you pass a string that is too long. Up to you to filter this.
    put(builder, count);
    append(builder, s.data, count);
    #if zero_terminated put(builder, cast(u8) 0);
}

get_short_string :: (input: *string, $count_type: Type, error: *bool, $allocate := true, $zero_terminated := false) -> string {
    T :: count_type;

    #assert((T == u8) || (T == u16) || (T == u32) || (T == s8) || (T == s16) || (T == s32));

    if input.count < size_of(T) {  // Not enough space in the string to hold the count!
        <<error = true;
        return;
    }
    
    result: string = ---;
    
    count: T;
    get(input, *count);

    if input.count < count {
        // There is not enough data in 'input' to cover what we want!
        <<error = true;
        return;
    }
    
    result.count = count;

    #if allocate_and_copy {
        result.data = alloc(count);
        if !result.data {
            <<error = true;
            return; // Since we are pretty low-level, we are leaving it up to the caller to log an error.
        }

        memcpy(result.data, input.data, count);
    } else {
        result.data  = input.data;
    }
    
    advance(input, count + cast(T) zero_terminated);
}
