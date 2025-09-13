///|
pub(all) struct Name {
  name : String?
  slot : Int
} derive(Eq, Hash, Compare)

///|
pub impl Show for Name with output(self : Name, logger : &Logger) -> Unit {
  logger.write_string(self.to_string())
}

///|
pub fn Name::to_string(self : Name) -> String {
  let { name, slot } = self
  match (name, slot) {
    (None, _) => "_\{slot}"
    (Some(name), 0) => name
    (Some(name), _) => "\{name}_\{slot}"
  }
}

///|
pub(all) suberror NameFromStringError {
  InvalidSlotNumber(String, String)
}

///|
pub impl Show for NameFromStringError with output(
  self : NameFromStringError,
  logger : &Logger,
) -> Unit {
  match self {
    NameFromStringError::InvalidSlotNumber(e, slot_s) =>
      logger.write_string("Invalid slot number: \{e} (input: \{slot_s})")
  }
}

///|
pub fn Name::from_string(s : String) -> Name raise NameFromStringError {
  match s.find(".") {
    Some(first_dot) => {
      let mut slot_s = ""
      try {
        let name = s[0:first_dot].to_string()
        slot_s = s[first_dot + 1:s.length()].to_string()
        let slot = @strconv.parse_int(slot_s, base=10)
        Name::name_and_slot(name, slot)
      } catch {
        @strconv.StrConvError(e) =>
          raise NameFromStringError::InvalidSlotNumber(e, slot_s)
        _ => raise NameFromStringError::InvalidSlotNumber(s, slot_s)
      }
    }
    None =>
      try {
        if s.has_prefix("_") &&
          s.length() > 1 &&
          s[1:s.length()].iter().all(fn(c) { c >= '0' && c <= '9' }) {
          let slot_s = s[1:s.length()].to_string()
          let slot = @strconv.parse_int(slot_s, base=10)
          Name::slot_only(slot)
        } else {
          Name::name_only(s)
        }
      } catch {
        @strconv.StrConvError(e) =>
          raise NameFromStringError::InvalidSlotNumber(e, s.to_string())
        _ => raise NameFromStringError::InvalidSlotNumber(s, s.to_string())
      }
  }
}

///|
pub fn Name::name_only(name : String) -> Name {
  { name: Some(name), slot: 0 }
}

///|
pub fn Name::name_and_slot(name : String, slot : Int) -> Name {
  { name: Some(name), slot }
}

///|
pub fn Name::slot_only(slot : Int) -> Name {
  { name: None, slot }
}

///|
pub fn Name::to_json(self : Name) -> Json {
  self.to_string().to_json()
}

///|
pub impl ToJson for Name with to_json(self : Name) -> Json {
  self.to_string().to_json()
}

///|
pub fn Name::from_json(json : Json) -> Name raise {
  match json {
    Json::String(s) => Name::from_string(s)
    _ => fail("Name::from_json: expected a string, but got \{json}")
  }
}
