# Bubbling Actions

Send an action from any view to the nearest ancestor that handles it, without wiring every
view in between.

## Overview

A view sends an action with `bubble`. An ancestor routes it with `onBubble(_:)`.
The action travels up the view tree to the nearest installer whose route matches, however deep
the sender is. Views in between declare nothing and forward nothing.

```swift
// A child, at any depth
struct PostActions: View {
    @Environment(\.graniteBubble) var bubble
    let post: Post

    var body: some View {
        Button("Reply") { bubble(.reply, post) }
        Text("Edit").bubble(.edit)              // sends on tap; needs no declaration
    }
}

// An ancestor
PostCard(post: post)
    .onBubble {
        center.reply.on(.reply) { (post: Post) in Reply.Meta(post: post) }
        On(.edit) { showEditor() }
    }
```

## Sending

A tap needs no declaration: `bubble(_:)` and its overloads send
when the view is tapped, as `.route` pushes on tap.

To send from code, such as `onSubmit`, a task's completion, or a gesture, read the handle once
per view with `@Environment(\.graniteBubble) var bubble` and call it:

- `bubble(.name)` sends a named action that carries no value.
- `bubble(value)` sends a value, routed by its type alone.
- `bubble(.name, value)` sends a value under a name.

Each call returns whether a route took it, so a view can fall back when nothing above it
handles the action:

```swift
if !bubble(.showThread, comment) { ModalService.shared.showThread(comment) }
```

Declare names once, as constants on ``GraniteBubble/Name``:

```swift
extension GraniteBubble.Name {
    static let reply: Self = "reply"
    static let edit: Self = "edit"
}
```

## Routing

`onBubble(_:)` takes a list of routes, one per line. A closure is routed with
``On``:

```swift
.onBubble {
    On(.edit) { showEditor() }                                 // a name, no value
    On(.select) { (item: Item) in select(item) }               // a name and a value
    On { (community: Community) in open(community) }           // a type alone
}
```

A reducer is routed on the reducer itself, with `on`, so the reducer and what it runs with are
declared together. What its closure does depends on what the closure returns:

```swift
.onBubble {
    center.refresh.on(.refresh)                                         // sent as is
    center.viewCommunity.on()                                           // a view sends ViewCommunity.Meta
    center.upvote.on(.upvote) { (post: Post) in Vote.Meta(post, .up) }  // returns the payload: a mapper
    center.bookmark.on(.bookmark) { (post: Post) in Bookmark.Meta(post) }
    center.vote.on(.vote) { Vote.Meta(currentPost, .up) }               // built from the installer's state
    center.edit.on(.edit) { GraniteHaptic.light.invoke() }              // returns Void: runs first, then sends
    center.save.on(.save) { (meta: Save.Meta) in dismiss() }            // the same, with the payload
}
```

- A closure that returns the reducer's payload is a **mapper**. Granite sends what it returns,
  so several reducers can take the same input under different names.
- A closure that returns `Void` is a **side effect**. It runs, then the reducer is sent the
  bubbled payload, or a bare send when the reducer takes none.

A bare reducer line is a compile error ("route a reducer with .on(…)"). Conditions belong
inside a route's closure, because the list itself is fixed.

## Keys and resolution

A route's key is an optional name plus the **exact** type sent:

- Bubbling looks at the nearest installer first, then at each installer above it, and stops
  at the first route whose key matches.
- An action no route matches passes on up. Nothing runs if it reaches the top.
- To stop an action at a level, route it there and do nothing: `On(.viewCommunity) { (_: Community) in }`.
- Types are matched exactly. A sent `Optional<X>` doesn't reach a route for `X`, and a concrete
  view doesn't reach a route for `any Modal`. Where a call site's static type can differ from the
  route's, cast it: `bubble(.present, alert as any Modal)`.
- String literals are names, so `bubble("x")` sends the name `x`. Bubble a string value from a
  variable, or route it as `String`.

In debug builds, an installer traps on two routes with the same key, and on an unnamed route
that sends nothing, which no bubble could reach. A bubble whose name matches a route but whose
type doesn't logs a warning that names both types.

## Memory

- **Senders and intermediate views** store nothing per action. A view holds at most one
  handle, which references its installer weakly.
- **Installers.** Each `onBubble(_:)` keeps one node for its view's lifetime,
  through `@StateObject`, not one per redraw. Each redraw builds one array of routes, and every
  route stores its closure or reducer inline, with no box.
- **Redraws.** The handle passed down stays equal across redraws, because the node is the
  same. Views reading it aren't invalidated when the installer's parent redraws, and routes
  are read when an action is sent, so the latest closures always run.
- **Retention.** Nothing points up the chain strongly. A copy of a view that outlives its
  installer, such as one kept by a coordinator or a presented builder, keeps none of the
  installer's routes alive, and its bubbles return `false`.

## Representables and presented content

A representable's coordinator should take the handle from the context, not from a copy of the
representable:

```swift
func updateUIViewController(_ controller: Picker, context: Context) {
    context.coordinator.bubble = context.environment.graniteBubble
}
```

Content shown in a separate window, or pushed onto a navigation stack, isn't under the view that
presented it. Install `onBubble(_:)` on that content's root:

```swift
presentSheet {
    Editor(post: post)
        .onBubble { On(.saved) { (post: Post) in update(post); dismissSheet() } }
}
```

## Migrating from GraniteAction

| GraniteAction | Bubbling |
|---|---|
| `@GraniteAction<T> var x` on the child | removed; one `@Environment(\.graniteBubble) var bubble` per view that sends from code |
| `x.perform(value)` / `x.perform()` | `bubble(.x, value)` / `bubble(.x)` |
| `.attach({ value in … }, at: \.x)` | `.onBubble { On(.x) { (value: T) in … } }` |
| `.attach(reducer, at: \.x)` | `.onBubble { reducer.on(.x) }` |
| `.attach(x, at: \.x)` (forwarding) | removed: bubbles pass through |
| `.attach(y, at: \.x)` (renaming) | `On(.x) { bubble(.y) }` |
| `attachAndClear` on presented content | `.onBubble` on that content's root |
| `GraniteActionable` | removed; a class sends through a service, a coordinator through the handle |

An action no parent attached used to do nothing. A bubble keeps going up, so where an ancestor
routes the same key, add a stop route at the level that used to ignore it.

## Topics

### Sending and routing

- ``GraniteBubble``
- ``GraniteBubble/Name``
- ``On``
- ``GraniteBubbleBuilder``
