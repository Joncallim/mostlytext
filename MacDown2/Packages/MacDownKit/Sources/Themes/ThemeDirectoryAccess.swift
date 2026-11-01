import Darwin

enum ThemeDirectoryAccess {
    /// Mode 0700 alone does not exclude access granted by an extended ACL.
    /// Keep deny-only protections, but do not silently remove user ACLs.
    static func hasOnlyDenyACL(_ descriptor: Int32) throws -> Bool {
        guard let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) else {
            if errno == ENOATTR || errno == ENOENT {
                return true
            }
            throw ThemeStorageError.unavailable(errno)
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        guard acl_valid(acl) == 0 else { throw ThemeStorageError.unavailable(errno) }
        var entry: acl_entry_t?
        var selector: Int32 = 0 // ACL_FIRST_ENTRY
        var count = 0
        while true {
            let result = acl_get_entry(acl, selector, &entry)
            // Darwin returns 0 for an entry and EINVAL at the end of a
            // validated ACL; its convention differs from Linux's API.
            if result != 0 {
                guard errno == EINVAL else { throw ThemeStorageError.unavailable(errno) }
                return true
            }
            guard let entry else { throw ThemeStorageError.invalidDirectory }
            count += 1
            guard count <= 1024 else { throw ThemeStorageError.invalidDirectory }
            var tag = ACL_UNDEFINED_TAG
            guard acl_get_tag_type(entry, &tag) == 0 else { throw ThemeStorageError.unavailable(errno) }
            guard tag == ACL_EXTENDED_DENY else { return false }
            selector = -1 // ACL_NEXT_ENTRY in the Darwin SDK.
        }
    }
}
