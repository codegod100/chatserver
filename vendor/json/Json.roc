## JSON is a data format that is easy for humans to read and write.
## This type provides a JSON format for encoding and decoding.

Json := [
    Utf8({ skip_missing_properties : Bool, null_decode_as_empty : Bool }),
].{
    ## Returns a JSON format with default settings
    utf8 : Json
    utf8 = Json.Utf8({ skip_missing_properties: True, null_decode_as_empty: True })
}
