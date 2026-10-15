///|
/// 0447: a type RE-EXPORTED under another name carries its MEMBERS with it, and
/// until this the analyzer could see the re-exported name but not what it stood
/// for.
///
/// THE FINDING, and it was the last 2 actionable findings in existence across the
/// six corpora. moonbit-community/proton 0.3.4 `facade_notification.mbt:12,14`
///
///     gate: @async.CondVar::Cond(),
///
/// reported `undefined function '@async.CondVar::Cond'` on both lines, on code
/// the toolchain accepts. moonbitlang/async 0.22.4 re-exports the type under
/// that name in `src/pkg.generated.mbti:111`:
///
///     pub using @cond_var {type Cond as CondVar}
///
/// and `@cond_var/pkg.generated.mbti` declares `type Cond` with
/// `pub fn Cond::Cond() -> Self`.
///
/// BOTH HALVES WERE ALREADY IN THE TABLE. The re-exported NAME, because the
/// `using` branch pushed it into `declared`; and `Cond::Cond`, because
/// `@cond_var`'s own interface is read and its signatures are bare. Nothing
/// connected them. `has_value` tries the exact key and then `unqualified`, so
/// `@async.CondVar::Cond` became `CondVar::Cond`, found nothing, and reported a
/// name that is written down two files away.
///
/// SETTLED WITH THE TOOLCHAIN, in `_verify/settle_0447_condvar_alias.ps1`, 6/6
/// with three negative controls firing: a constructor IS callable through an
/// aliased type re-export, cross-package, and a name that does NOT exist is
/// still rejected through it. That second half is the reason this is a LINK and
/// not a suppression — see the controls below.

///|
/// The finding, at the seam the analyzer actually looks in. Two tables, exactly
/// as `collect_iface_symtabs` builds them: every `.mbti` of the tree merged into
/// one flat table.
test "0447: a re-exported type's members resolve through the re-exported name" {
  // `@cond_var/pkg.generated.mbti` -- the inner package.
  let inner = @moonfiles.collect_iface_names(
    "type Cond\npub fn Cond::Cond() -> Self\npub fn Cond::broadcast(Self) -> Unit\n",
  )
  // async `src/pkg.generated.mbti:111` -- the outer re-export.
  let outer = @moonfiles.collect_iface_names(
    "pub using @cond_var {type Cond as CondVar}\n",
  )
  let tab = inner.merge(outer)
  // Both of these were TRUE before this change and are the reason the finding
  // looked like a missing declaration rather than a missing link.
  assert_true(tab.has_type("CondVar"))
  assert_true(tab.has_value("Cond::Cond"))
  // These are what it could not do.
  assert_true(tab.has_value("CondVar::Cond"))
  assert_true(tab.has_value("@async.CondVar::Cond"))
  // not just the constructor: any member of the re-exported type
  assert_true(tab.has_value("CondVar::broadcast"))
  assert_true(tab.has_value("@async.CondVar::broadcast"))
}

///|
/// THE CONTROLS, and they are the reason the fix is a link rather than a
/// blanket suppression. Settled by measurement: `moon check` rejects
/// `@p0447.CondVar::Nope()` with `[4029]` and a nonexistent type with `[4032]`,
/// so the toolchain does NOT forgive an arbitrary member through a re-export.
/// If the analyzer forgave it, it would be trading a false positive for a false
/// negative — and a corpus cannot tell the difference.
test "0447: the alias link silences nothing that is not there" {
  let inner = @moonfiles.collect_iface_names(
    "type Cond\npub fn Cond::Cond() -> Self\n",
  )
  let outer = @moonfiles.collect_iface_names(
    "pub using @cond_var {type Cond as CondVar}\n",
  )
  let tab = inner.merge(outer)
  // a member that does not exist on the re-exported type
  assert_false(tab.has_value("CondVar::Nope"))
  assert_false(tab.has_value("@async.CondVar::Nope"))
  // a HEAD that is not an alias at all
  assert_false(tab.has_value("@async.Nope::Cond"))
  // and the real declaration is still reachable directly, which is what proves
  // the controls are asking about the alias and not about a broken table
  assert_true(tab.has_value("Cond::Cond"))
}

///|
/// THE CONTROL THAT PINS WHERE THE LINK COMES FROM. A module that declares
/// `CondVar` ITSELF, having re-exported nothing, has a real type called
/// `CondVar` — and must NOT inherit `Cond`'s members just because some other
/// module in the same flat table re-exported a type under that name.
///
/// Without this, "the head name is in `aliases`" would be indistinguishable
/// from "the head name happens to match".
test "0447: a locally declared type of the same name creates no link" {
  let inner = @moonfiles.collect_iface_names(
    "type Cond\npub fn Cond::Cond() -> Self\n",
  )
  // declared, not re-exported: `parse_iface`'s `using` branch never sees this
  // (`own`, not `local` -- `local` is a MoonBit reserved keyword and
  // `moon check --deny-warn` turns that into an error)
  let own = @moonfiles.collect_iface_names(
    "type CondVar\npub fn CondVar::new() -> Self\n",
  )
  let tab = inner.merge(own)
  assert_true(tab.has_type("CondVar"))
  assert_true(tab.has_value("CondVar::new"))
  // `CondVar` is NOT an alias for `Cond` here, so `Cond`'s constructor must not
  // be borrowed under that name.
  assert_false(tab.has_value("CondVar::Cond"))
}

///|
/// A re-export WITHOUT `as` renames nothing, so there is no second name to link
/// and nothing should change. `moonbitlang/async` writes
/// `pub using @aqueue {type Queue}` on the line after the `CondVar` one, so this
/// is the shape that sits beside the finding in the real file.
test "0447: a re-export without `as` records no link" {
  let inner = @moonfiles.collect_iface_names(
    "type Queue\npub fn Queue::new() -> Self\n",
  )
  let outer = @moonfiles.collect_iface_names("pub using @aqueue {type Queue}\n")
  let tab = inner.merge(outer)
  assert_true(tab.has_type("Queue"))
  assert_true(tab.has_value("Queue::new"))
  // No alias was recorded, so nothing is rewritten. `Queue` names itself.
  assert_false(tab.has_value("CondVar::new"))
}

///|
/// `merge` and `union` both have to carry the alias map, or a table that arrives
/// through either loses the link and the finding comes back with no code change
/// to point at. `union` is the one `collect_private_symtabs` uses.
test "0447: the alias survives both merge and union" {
  let inner = @moonfiles.collect_iface_names(
    "type Cond\npub fn Cond::Cond() -> Self\n",
  )
  let outer = @moonfiles.collect_iface_names(
    "pub using @cond_var {type Cond as CondVar}\n",
  )
  assert_true(outer.merge(inner).has_value("CondVar::Cond"))
  assert_true(inner.merge(outer).has_value("CondVar::Cond"))
  assert_true(inner.union(outer).has_value("CondVar::Cond"))
  assert_true(outer.union(inner).has_value("CondVar::Cond"))
}
