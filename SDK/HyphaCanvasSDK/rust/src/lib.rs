#![forbid(unsafe_code)]

pub const BRIDGE_VERSION: u8 = 1;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Method {
    RoomGetMetadata,
    RepositoriesList,
    AssetsList,
    AssetsGetMetadata,
    AssetsGetUrl,
    ViewerOpen,
    LayoutStateGet,
    LayoutStateSet,
}

impl Method {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::RoomGetMetadata => "room.get_metadata",
            Self::RepositoriesList => "repositories.list",
            Self::AssetsList => "assets.list",
            Self::AssetsGetMetadata => "assets.get_metadata",
            Self::AssetsGetUrl => "assets.get_url",
            Self::ViewerOpen => "viewer.open",
            Self::LayoutStateGet => "layout_state.get",
            Self::LayoutStateSet => "layout_state.set",
        }
    }
}

pub fn request_json(id: &str, method: Method, params_json: &str) -> Result<String, &'static str> {
    if id.is_empty() || id.len() > 128 || id.bytes().any(|value| value < 0x20) {
        return Err("invalid request id");
    }
    let params = params_json.trim();
    if !params.starts_with('{') || !params.ends_with('}') || params.len() > 65_536 {
        return Err("invalid params object");
    }
    Ok(format!(
        "{{\"v\":{},\"id\":\"{}\",\"method\":\"{}\",\"params\":{}}}",
        BRIDGE_VERSION,
        escape_json(id),
        method.as_str(),
        params
    ))
}

fn escape_json(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn emits_the_same_version_and_method_names_as_typescript() {
        let request = request_json("abc", Method::AssetsList, "{}").unwrap();
        assert_eq!(request, "{\"v\":1,\"id\":\"abc\",\"method\":\"assets.list\",\"params\":{}}");
    }
}
