## Convert between various ASCII string formats.
## `PascalCase`
## `snake_case`
## `camelCase`
## `kabab-case`
module [
    Format,
    convert_case,
]

Format := [
    SnakeCase,
    PascalCase,
    KebabCase,
    CamelCase,
]

## Convert an ASCII string between various formats
convert_case : Str, { from : Format, to : Format } -> Try(Str, [NotASCII, ..others])
convert_case = |str, config| {
    # confirm Str is ASCII
    bytes = str.to_utf8()
    is_ascii = bytes.all(|b| b >= 0 and b <= 127)

    if is_ascii {
        match (config.from, config.to) {
            (Format.CamelCase, Format.CamelCase) => Ok(str)
            (Format.KebabCase, Format.KebabCase) => Ok(str)
            (Format.PascalCase, Format.PascalCase) => Ok(str)
            (Format.SnakeCase, Format.SnakeCase) => Ok(str)

            (Format.SnakeCase, Format.PascalCase) => Ok(snake_to_pascal(str))
            (Format.SnakeCase, Format.KebabCase) => Ok(snake_to_kebab(str))
            (Format.SnakeCase, Format.CamelCase) => Ok(snake_to_camel(str))
            (Format.KebabCase, Format.SnakeCase) => Ok(kebab_to_snake(str))
            (Format.KebabCase, Format.CamelCase) => Ok(kebab_to_camel(str))
            (Format.KebabCase, Format.PascalCase) => Ok(kebab_to_pascal(str))
            (Format.PascalCase, Format.SnakeCase) => pascal_to_snake(str).map_err(|_| NotASCII)
            (Format.PascalCase, Format.CamelCase) => pascal_to_camel(str).map_err(|_| NotASCII)
            (Format.PascalCase, Format.KebabCase) => pascal_to_kebab(str).map_err(|_| NotASCII)
            (Format.CamelCase, Format.SnakeCase) => camel_to_snake(str).map_err(|_| NotASCII)
            (Format.CamelCase, Format.PascalCase) => camel_to_pascal(str).map_err(|_| NotASCII)
            (Format.CamelCase, Format.KebabCase) => camel_to_kebab(str).map_err(|_| NotASCII)
            _ => Err(NotASCII)
        }
    } else {
        Err(NotASCII)
    }
}

snake_to_pascal : Str -> Str
snake_to_pascal = |str| {
    str.split_on("_")
        .map(uppercase_first_ascii)
        .keep_if(|r| match r { Ok(_) => True; Err(_) => False })
        .map(|r| match r { Ok(s) => s; Err(_) => "" })
        .join_with("")
}

snake_to_kebab : Str -> Str
snake_to_kebab = |str| str.split_on("_").join_with("-")

snake_to_camel : Str -> Str
snake_to_camel = |str| match str.split_on("_") {
    [first, .. as rest] => {
        rest_pascal = rest
            .map(uppercase_first_ascii)
            .keep_if(|r| match r { Ok(_) => True; Err(_) => False })
            .map(|r| match r { Ok(s) => s; Err(_) => "" })
            .join_with("")
        first.concat(rest_pascal)
    }
    _ => str
}

kebab_to_snake : Str -> Str
kebab_to_snake = |str| str.split_on("-").join_with("_")

kebab_to_camel : Str -> Str
kebab_to_camel = |str| match str.split_on("-") {
    [first, .. as rest] => {
        rest_pascal = rest
            .map(uppercase_first_ascii)
            .keep_if(|r| match r { Ok(_) => True; Err(_) => False })
            .map(|r| match r { Ok(s) => s; Err(_) => "" })
            .join_with("")
        first.concat(rest_pascal)
    }
    _ => str
}

kebab_to_pascal : Str -> Str
kebab_to_pascal = |str| {
    str.split_on("-")
        .map(uppercase_first_ascii)
        .keep_if(|r| match r { Ok(_) => True; Err(_) => False })
        .map(|r| match r { Ok(s) => s; Err(_) => "" })
        .join_with("")
}

pascal_to_snake : Str -> Try(Str, [InvalidPascal, ..others])
pascal_to_snake = |str| {
    segments = split_pascal(str)?
    segments
        .map(lowercase_str)
        .join_with("_")
        .Ok()
}

pascal_to_camel : Str -> Try(Str, [BadUtf8, ..others])
pascal_to_camel = |str| match str.to_utf8() {
    [first, .. as rest] => {
        rest.prepend(to_lowercase(first)).to_str()
    }
    _ => Ok(str)
}

pascal_to_kebab : Str -> Try(Str, [InvalidPascal, ..others])
pascal_to_kebab = |str| {
    segments = split_pascal(str)?
    segments
        .map(lowercase_str)
        .join_with("-")
        .Ok()
}

camel_to_snake : Str -> Try(Str, [InvalidCamel, ..others])
camel_to_snake = |str| {
    segments = split_camel(str)?
    segments
        .map(lowercase_str)
        .join_with("_")
        .Ok()
}

camel_to_pascal : Str -> Try(Str, [BadUtf8, ..others])
camel_to_pascal = |str| match str.to_utf8() {
    [first, .. as rest] => {
        rest.prepend(to_uppercase(first)).to_str()
    }
    _ => Ok(str)
}

camel_to_kebab : Str -> Try(Str, [InvalidCamel, ..others])
camel_to_kebab = |str| {
    segments = split_camel(str)?
    segments
        .map(lowercase_str)
        .join_with("-")
        .Ok()
}

uppercase_first_ascii : Str -> Try(Str, [BadUtf8, ..others])
uppercase_first_ascii = |str| match str.to_utf8() {
    [first, .. as rest] => rest.prepend(to_uppercase(first)).to_str()
    _ => Ok(str)
}

to_uppercase : U8 -> U8
to_uppercase = |byte| {
    if byte >= 'a' and byte <= 'z' {
        byte - 32
    } else {
        byte
    }
}

to_lowercase : U8 -> U8
to_lowercase = |byte| {
    if byte >= 'A' and byte <= 'Z' {
        byte + 32
    } else {
        byte
    }
}

lowercase_str : Str -> Str
lowercase_str = |str| {
    bytes = str.to_utf8().map(to_lowercase)
    match bytes.to_str() {
        Ok(s) => s
        Err(_) => str
    }
}

is_lower_case : U8 -> Bool
is_lower_case = |byte| byte >= 'a' and byte <= 'z'

is_digit : U8 -> Bool
is_digit = |byte| byte >= '0' and byte <= '9'

is_upper_case : U8 -> Bool
is_upper_case = |byte| byte >= 'A' and byte <= 'Z'

SplitCaseState := [
    StartCamel,
    StartPascal,
    Upper(U64, List({ start : U64, len : U64 })),
    Number(U64, List({ start : U64, len : U64 })),
    Lower(U64, List({ start : U64, len : U64 })),
    Invalid,
]

split_pascal : Str -> Try(List(Str), [InvalidPascal, ..others])
split_pascal = |str| {
    ascii_bytes = str.to_utf8()
    ascii_bytes_len = ascii_bytes.len()

    final_state = ascii_bytes.fold(
        { state: SplitCaseState.StartPascal, index: 0 },
        |acc, byte| {
            new_state = split_case_step(acc.state, byte, acc.index)
            { state: new_state, index: acc.index + 1 }
        },
    )

    match final_state.state {
        SplitCaseState.Invalid => Err(InvalidPascal)
        SplitCaseState.StartCamel => Ok([])
        SplitCaseState.StartPascal => Ok([])
        SplitCaseState.Upper(start, indexes) => {
            all_indexes = indexes.append({ start: start, len: ascii_bytes_len - start })
            extract_slices(ascii_bytes, all_indexes)
        }
        SplitCaseState.Number(start, indexes) => {
            all_indexes = indexes.append({ start: start, len: ascii_bytes_len - start })
            extract_slices(ascii_bytes, all_indexes)
        }
        SplitCaseState.Lower(start, indexes) => {
            all_indexes = indexes.append({ start: start, len: ascii_bytes_len - start })
            extract_slices(ascii_bytes, all_indexes)
        }
    }
}

split_camel : Str -> Try(List(Str), [InvalidCamel, ..others])
split_camel = |str| {
    ascii_bytes = str.to_utf8()
    ascii_bytes_len = ascii_bytes.len()

    final_state = ascii_bytes.fold(
        { state: SplitCaseState.StartCamel, index: 0 },
        |acc, byte| {
            new_state = split_case_step(acc.state, byte, acc.index)
            { state: new_state, index: acc.index + 1 }
        },
    )

    match final_state.state {
        SplitCaseState.Invalid => Err(InvalidCamel)
        SplitCaseState.StartCamel => Ok([])
        SplitCaseState.StartPascal => Ok([])
        SplitCaseState.Upper(start, indexes) => {
            all_indexes = indexes.append({ start: start, len: ascii_bytes_len - start })
            extract_slices(ascii_bytes, all_indexes).map_err(|_| InvalidCamel)
        }
        SplitCaseState.Number(start, indexes) => {
            all_indexes = indexes.append({ start: start, len: ascii_bytes_len - start })
            extract_slices(ascii_bytes, all_indexes).map_err(|_| InvalidCamel)
        }
        SplitCaseState.Lower(start, indexes) => {
            all_indexes = indexes.append({ start: start, len: ascii_bytes_len - start })
            extract_slices(ascii_bytes, all_indexes).map_err(|_| InvalidCamel)
        }
    }
}

split_case_step : SplitCaseState, U8, U64 -> SplitCaseState
split_case_step = |state, byte, index| match state {
    SplitCaseState.Invalid => SplitCaseState.Invalid
    SplitCaseState.StartCamel => if is_lower_case(byte) { SplitCaseState.Lower(index, []) } else { SplitCaseState.Invalid }
    SplitCaseState.StartPascal => if is_upper_case(byte) { SplitCaseState.Upper(index, []) } else { SplitCaseState.Invalid }
    SplitCaseState.Upper(start, indexes) => {
        if is_upper_case(byte) {
            SplitCaseState.Upper(start, indexes)
        } else if is_digit(byte) {
            SplitCaseState.Number(start, indexes)
        } else if is_lower_case(byte) {
            if (index - start) > 1 {
                SplitCaseState.Lower(index - 1, indexes.append({ start: start, len: index - start - 1 }))
            } else {
                SplitCaseState.Lower(start, indexes)
            }
        } else {
            SplitCaseState.Invalid
        }
    }
    SplitCaseState.Number(start, indexes) => {
        if is_digit(byte) {
            SplitCaseState.Number(start, indexes)
        } else if is_lower_case(byte) {
            SplitCaseState.Lower(start, indexes)
        } else if is_upper_case(byte) {
            SplitCaseState.Upper(index, indexes.append({ start: start, len: index - start }))
        } else {
            SplitCaseState.Invalid
        }
    }
    SplitCaseState.Lower(start, indexes) => {
        if is_lower_case(byte) {
            SplitCaseState.Lower(start, indexes)
        } else if is_digit(byte) {
            SplitCaseState.Number(start, indexes)
        } else if is_upper_case(byte) {
            SplitCaseState.Upper(index, indexes.append({ start: start, len: index - start }))
        } else {
            SplitCaseState.Invalid
        }
    }
}

extract_slices : List(U8), List({ start : U64, len : U64 }) -> Try(List(Str), [InvalidPascal, ..others])
extract_slices = |bytes, indexes| {
    slices = indexes.map(|{ start, len }| bytes.sublist({ start: start, len: len }))
    strings = slices.map(|slice| slice.to_str())

    # Check if all conversions succeeded
    has_error = strings.any(|r| match r { Err(_) => True; Ok(_) => False })
    if has_error {
        Err(InvalidPascal)
    } else {
        Ok(strings.map(|r| match r { Ok(s) => s; Err(_) => "" }))
    }
}
