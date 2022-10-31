// Copyright 2014 The Flutter Authors.
// Copyright 2021 Suragch.
// All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui hide TextStyle;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart'
    show
        DeleteToNextWordBoundaryIntent,
        ExpandSelectionToDocumentBoundaryIntent,
        ExtendSelectionVerticallyToAdjacentLineIntent,
        ReplaceTextIntent,
        ScrollToDocumentBoundaryIntent,
        Size,
        kMinInteractiveDimension;
import 'package:flutter/rendering.dart'
    show CaretChangedHandler, RevealedOffset, ViewportOffset;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show
        Action,
        Actions,
        AnimationController,
        AppPrivateCommandCallback,
        AutofillGroup,
        AutofillGroupState,
        AutomaticKeepAliveClientMixin,
        AxisDirection,
        BuildContext,
        CallbackAction,
        CharacterRange,
        Clip,
        ClipboardStatus,
        ClipboardStatusNotifier,
        Color,
        CompositedTransformTarget,
        ContextAction,
        CopySelectionTextIntent,
        Curve,
        Curves,
        DeleteCharacterIntent,
        DeleteToLineBreakIntent,
        DirectionalCaretMovementIntent,
        DirectionalFocusAction,
        DirectionalFocusIntent,
        DirectionalTextEditingIntent,
        DismissIntent,
        DoNothingAction,
        DoNothingAndStopPropagationTextIntent,
        EdgeInsets,
        ExpandSelectionToLineBreakIntent,
        ExtendSelectionByCharacterIntent,
        ExtendSelectionToDocumentBoundaryIntent,
        ExtendSelectionToLineBreakIntent,
        ExtendSelectionToNextWordBoundaryIntent,
        ExtendSelectionToNextWordBoundaryOrCaretLocationIntent,
        Focus,
        FocusAttachment,
        FocusNode,
        FocusScope,
        GlobalKey,
        Intent,
        LayerLink,
        LeafRenderObjectWidget,
        MediaQuery,
        MouseRegion,
        Offset,
        PasteTextIntent,
        Radius,
        Rect,
        ScrollBehavior,
        ScrollConfiguration,
        ScrollController,
        ScrollPhysics,
        Scrollable,
        SelectAllTextIntent,
        SelectionChangedCallback,
        Semantics,
        State,
        StatefulWidget,
        TextAlign,
        TextDirection,
        TextEditingController,
        TextSelectionControls,
        TextSelectionHandleType,
        TextSpan,
        TextStyle,
        TickerProviderStateMixin,
        ToolbarOptions,
        UpdateSelectionIntent,
        Widget,
        WidgetsBinding,
        WidgetsBindingObserver,
        debugCheckHasMediaQuery;
//import 'package:flutter/widgets.dart' hide EditableText, EditableTextState;

import 'package:mongol/src/base/mongol_text_align.dart';
import 'package:mongol/src/editing/default_mongol_text_editing_shortcuts.dart';
import 'package:mongol/src/editing/mongol_render_editable.dart';
import 'package:mongol/src/editing/text_selection/mongol_text_selection.dart';

import 'mongol_text_editing_action.dart';

export 'package:flutter/services.dart'
    show
        SelectionChangedCause,
        TextEditingValue,
        TextSelection,
        TextInputType,
        SmartQuotesType,
        SmartDashesType;

// The time it takes for the cursor to fade from fully opaque to fully
// transparent and vice versa. A full cursor blink, from transparent to opaque
// to transparent, is twice this duration.
const Duration _kCursorBlinkHalfPeriod = Duration(milliseconds: 500);

// The time the cursor is static in opacity before animating to become
// transparent.
const Duration _kCursorBlinkWaitForStart = Duration(milliseconds: 150);

// Number of cursor ticks during which the most recently entered character
// is shown in an obscured text field.
const int _kObscureShowLatestCharCursorTicks = 3;

/// A basic text input field.
///
/// This widget interacts with the [TextInput] service to let the user edit the
/// text it contains. It also provides scrolling, selection, and cursor
/// movement. This widget does not provide any focus management (e.g.,
/// tap-to-focus).
///
/// ## Handling User Input
///
/// Currently the user may change the text this widget contains via keyboard or
/// the text selection menu. When the user inserted or deleted text, you will be
/// notified of the change and get a chance to modify the new text value:
///
/// * The [inputFormatters] will be first applied to the user input.
///
/// * The [controller]'s [TextEditingController.value] will be updated with the
///   formatted result, and the [controller]'s listeners will be notified.
///
/// * The [onChanged] callback, if specified, will be called last.
///
/// ## Input Actions
///
/// A [TextInputAction] can be provided to customize the appearance of the
/// action button on the soft keyboard for Android and iOS. The default action
/// is [TextInputAction.done].
///
/// Many [TextInputAction]s are common between Android and iOS. However, if a
/// [textInputAction] is provided that is not supported by the current
/// platform in debug mode, an error will be thrown when the corresponding
/// MongolEditableText receives focus. For example, providing iOS's "emergencyCall"
/// action when running on an Android device will result in an error when in
/// debug mode. In release mode, incompatible [TextInputAction]s are replaced
/// either with "unspecified" on Android, or "default" on iOS. Appropriate
/// [textInputAction]s can be chosen by checking the current platform and then
/// selecting the appropriate action.
///
/// ## Lifecycle
///
/// Upon completion of editing, like pressing the "done" button on the keyboard,
/// two actions take place:
///
///   1st: Editing is finalized. The default behavior of this step includes
///   an invocation of [onChanged]. That default behavior can be overridden.
///   See [onEditingComplete] for details.
///
///   2nd: [onSubmitted] is invoked with the user's input value.
///
/// [onSubmitted] can be used to manually move focus to another input widget
/// when a user finishes with the currently focused input widget.
///
/// Rather than using this widget directly, consider using [MongolTextField], which
/// is a full-featured, material-design text input field with placeholder text,
/// labels, and [Form] integration.
///
/// ## Gesture Events Handling
///
/// This widget provides rudimentary, platform-agnostic gesture handling for
/// user actions such as tapping, long-pressing and scrolling when
/// [rendererIgnoresPointer] is false (false by default). For custom selection
/// behavior, call methods such as [MongolRenderEditable.selectPosition],
/// [MongolRenderEditable.selectWord], etc. programmatically.
///
/// See also:
///
///  * [MongolTextField], which is a full-featured, material-design text input
///    field with placeholder text, labels, and [Form] integration.
class MongolEditableText extends StatefulWidget {
  /// Creates a basic text input control.
  ///
  /// The [maxLines] property can be set to null to remove the restriction on
  /// the number of lines. By default, it is one, meaning this is a single-line
  /// text field. [maxLines] must be null or greater than zero.
  ///
  /// If [keyboardType] is not set or is null, its value will be inferred from
  /// [autofillHints], if [autofillHints] is not empty. Otherwise it defaults to
  /// [TextInputType.text] if [maxLines] is exactly one, and
  /// [TextInputType.multiline] if [maxLines] is null or greater than one.
  ///
  /// The text cursor is not shown if [showCursor] is false or if [showCursor]
  /// is null (the default) and [readOnly] is true.
  MongolEditableText({
    Key? key,
    required this.controller,
    required this.focusNode,
    this.readOnly = false,
    this.obscuringCharacter = '•',
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    required this.style,
    required this.cursorColor,
    this.textAlign = MongolTextAlign.top,
    this.textScaleFactor,
    this.maxLines = 1,
    this.minLines,
    this.expands = false,
    this.forceLine = true,
    this.autofocus = false,
    bool? showCursor,
    this.showSelectionHandles = false,
    this.selectionColor,
    this.selectionControls,
    TextInputType? keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.onAppPrivateCommand,
    this.onSelectionChanged,
    this.onSelectionHandleTapped,
    List<TextInputFormatter>? inputFormatters,
    this.mouseCursor,
    this.rendererIgnoresPointer = false,
    this.cursorHeight = 2.0,
    this.cursorWidth,
    this.cursorRadius,
    this.cursorOpacityAnimates = false,
    this.cursorOffset,
    this.scrollPadding = const EdgeInsets.all(20.0),
    this.keyboardAppearance = Brightness.light,
    this.dragStartBehavior = DragStartBehavior.start,
    this.enableInteractiveSelection = true,
    this.scrollController,
    this.scrollPhysics,
    this.toolbarOptions = const ToolbarOptions(
      copy: true,
      cut: true,
      paste: true,
      selectAll: true,
    ),
    this.autofillHints,
    this.autofillClient,
    this.clipBehavior = Clip.hardEdge,
    this.restorationId,
    this.scrollBehavior,
  })  : assert(obscuringCharacter.length == 1),
        assert(maxLines == null || maxLines > 0),
        assert(minLines == null || minLines > 0),
        assert(
          (maxLines == null) || (minLines == null) || (maxLines >= minLines),
          "minLines can't be greater than maxLines",
        ),
        assert(
          !expands || (maxLines == null && minLines == null),
          'minLines and maxLines must be null when expands is true.',
        ),
        assert(!obscureText || maxLines == 1,
            'Obscured fields cannot be multiline.'),
        assert(
          !readOnly || autofillHints == null,
          "Read-only fields can't have autofill hints.",
        ),
        keyboardType = keyboardType ??
            _inferKeyboardType(
                autofillHints: autofillHints, maxLines: maxLines),
        inputFormatters = maxLines == 1
            ? <TextInputFormatter>[
                FilteringTextInputFormatter.singleLineFormatter,
                ...inputFormatters ??
                    const Iterable<TextInputFormatter>.empty(),
              ]
            : inputFormatters,
        showCursor = showCursor ?? !readOnly,
        super(key: key);

  /// Controls the text being edited.
  final TextEditingController controller;

  /// Controls whether this widget has keyboard focus.
  final FocusNode focusNode;

  /// Character used for obscuring text if [obscureText] is true.
  ///
  /// Must be only a single character.
  ///
  /// Defaults to the character U+2022 BULLET (•).
  final String obscuringCharacter;

  /// Whether to hide the text being edited (e.g., for passwords).
  ///
  /// When this is set to true, all the characters in the text field are
  /// replaced by [obscuringCharacter].
  ///
  /// Defaults to false.
  final bool obscureText;

  /// Whether the text can be changed.
  ///
  /// When this is set to true, the text cannot be modified
  /// by any shortcut or keyboard operation. The text is still selectable.
  ///
  /// Defaults to false.
  final bool readOnly;

  /// Whether the text will take the full height regardless of the text height.
  ///
  /// When this is set to false, the height will be based on text height.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///  * [textWidthBasis], which controls the calculation of text width.
  final bool forceLine;

  /// Configuration of toolbar options.
  ///
  /// By default, all options are enabled. If [readOnly] is true,
  /// paste and cut will be disabled regardless.
  final ToolbarOptions toolbarOptions;

  /// Whether to show selection handles.
  ///
  /// When a selection is active, there will be two handles at each side of
  /// boundary, or one handle if the selection is collapsed. The handles can be
  /// dragged to adjust the selection.
  ///
  /// See also:
  ///
  ///  * [showCursor], which controls the visibility of the cursor.
  final bool showSelectionHandles;

  /// Whether to show cursor.
  ///
  /// The cursor refers to the blinking caret when the [MongolEditableText] is
  /// focused.
  ///
  /// See also:
  ///
  ///  * [showSelectionHandles], which controls the visibility of the selection
  ///    handles.
  final bool showCursor;

  /// Whether to enable autocorrection.
  ///
  /// Defaults to true. Cannot be null.
  final bool autocorrect;

  /// Whether to show input suggestions as the user types.
  ///
  /// This flag only affects Android. On iOS, suggestions are tied directly to
  /// [autocorrect], so that suggestions are only shown when [autocorrect] is
  /// true. On Android autocorrection and suggestion are controlled separately.
  ///
  /// Defaults to true.
  ///
  /// See also:
  ///
  ///  * <https://developer.android.com/reference/android/text/InputType.html#TYPE_TEXT_FLAG_NO_SUGGESTIONS>
  final bool enableSuggestions;

  /// The text style to use for the editable text.
  final TextStyle style;

  /// How the text should be aligned vertically.
  ///
  /// Defaults to [MongolTextAlign.top].
  final MongolTextAlign textAlign;

  /// The number of font pixels for each logical pixel.
  ///
  /// For example, if the text scale factor is 1.5, text will be 50% larger than
  /// the specified font size.
  ///
  /// Defaults to the [MediaQueryData.textScaleFactor] obtained from the ambient
  /// [MediaQuery], or 1.0 if there is no [MediaQuery] in scope.
  final double? textScaleFactor;

  /// The color to use when painting the cursor.
  final Color cursorColor;

  /// The maximum number of lines for the text to span, wrapping if necessary.
  ///
  /// If this is 1 (the default), the text will not wrap, but will scroll
  /// vertically instead.
  ///
  /// If this is null, there is no limit to the number of lines, and the text
  /// container will start with enough horizontal space for one line and
  /// automatically grow to accommodate additional lines as they are entered.
  ///
  /// If this is not null, the value must be greater than zero, and it will lock
  /// the input to the given number of lines and take up enough vertical space
  /// to accommodate that number of lines. Setting [minLines] as well allows the
  /// input to grow between the indicated range.
  ///
  /// The full set of behaviors possible with [minLines] and [maxLines] are as
  /// follows. These examples apply equally to `MongolTextField`,
  /// `MongolTextFormField`, and `MongolEditableText`.
  ///
  /// Input that occupies a single line and scrolls vertically as needed.
  /// ```dart
  /// MongolTextField()
  /// ```
  ///
  /// Input whose width grows from one line up to as many lines as needed for
  /// the text that was entered. If a width limit is imposed by its parent, it
  /// will scroll horizontally when its width reaches that limit.
  /// ```dart
  /// MongolTextField(maxLines: null)
  /// ```
  ///
  /// The input's width is large enough for the given number of lines. If
  /// additional lines are entered the input scrolls horizontally.
  /// ```dart
  /// MongolTextField(maxLines: 2)
  /// ```
  ///
  /// Input whose width grows with content between a min and max. An infinite
  /// max is possible with `maxLines: null`.
  /// ```dart
  /// MongolTextField(minLines: 2, maxLines: 4)
  /// ```
  final int? maxLines;

  /// The minimum number of lines to occupy when the content spans fewer lines.
  ///
  /// If this is null (default), text container starts with enough horizontal space
  /// for one line and grows to accommodate additional lines as they are entered.
  ///
  /// This can be used in combination with [maxLines] for a varying set of behaviors.
  ///
  /// If the value is set, it must be greater than zero. If the value is greater
  /// than 1, [maxLines] should also be set to either null or greater than
  /// this value.
  ///
  /// When [maxLines] is set as well, the width will grow between the indicated
  /// range of lines. When [maxLines] is null, it will grow as wide as needed,
  /// starting from [minLines].
  ///
  /// A few examples of behaviors possible with [minLines] and [maxLines] are as follows.
  /// These apply equally to `MongolTextField`, `MongolTextFormField`,
  /// and `MongolEditableText`.
  ///
  /// Input that always occupies at least 2 lines and has an infinite max.
  /// Expands horizontally as needed.
  /// ```dart
  /// MongolTextField(minLines: 2)
  /// ```
  ///
  /// Input whose width starts from 2 lines and grows up to 4 lines at which
  /// point the width limit is reached. If additional lines are entered it will
  /// scroll horizontally.
  /// ```dart
  /// MongolTextField(minLines:2, maxLines: 4)
  /// ```
  ///
  /// See the examples in [maxLines] for the complete picture of how [maxLines]
  /// and [minLines] interact to produce various behaviors.
  ///
  /// Defaults to null.
  final int? minLines;

  /// Whether this widget's width will be sized to fill its parent.
  ///
  /// If set to true and wrapped in a parent widget like [Expanded] or
  /// [SizedBox], the input will expand to fill the parent.
  ///
  /// [maxLines] and [minLines] must both be null when this is set to true,
  /// otherwise an error is thrown.
  ///
  /// Defaults to false.
  ///
  /// See the examples in [maxLines] for the complete picture of how [maxLines],
  /// [minLines], and [expands] interact to produce various behaviors.
  ///
  /// Input that matches the width of its parent:
  /// ```dart
  /// Expanded(
  ///   child: MongolTextField(maxLines: null, expands: true),
  /// )
  /// ```
  final bool expands;

  /// Whether this text field should focus itself if nothing else is already
  /// focused.
  ///
  /// If true, the keyboard will open as soon as this text field obtains focus.
  /// Otherwise, the keyboard is only shown after the user taps the text field.
  ///
  /// Defaults to false. Cannot be null.
  // See https://github.com/flutter/flutter/issues/7035 for the rationale for this
  // keyboard behavior.
  final bool autofocus;

  /// The color to use when painting the selection.
  ///
  /// For [MongolTextField]s, the value is set to the ambient
  /// [ThemeData.textSelectionColor].
  final Color? selectionColor;

  /// Optional delegate for building the text selection handles and toolbar.
  ///
  /// The [MongolEditableText] widget used on its own will not trigger the display
  /// of the selection toolbar by itself. The toolbar is shown by calling
  /// [EditableTextState.showToolbar] in response to an appropriate user event.
  ///
  /// See also:
  ///
  ///  * [MongolTextField], a Material Design themed wrapper of
  ///    [MongolEditableText], which shows the selection toolbar upon
  ///    appropriate user events based on the user's platform set in
  ///    [ThemeData.platform].
  final TextSelectionControls? selectionControls;

  /// The type of keyboard to use for editing the text.
  ///
  /// Defaults to [TextInputType.text] if [maxLines] is one and
  /// [TextInputType.multiline] otherwise.
  final TextInputType keyboardType;

  /// The type of action button to use with the soft keyboard.
  final TextInputAction? textInputAction;

  /// Called when the user initiates a change to the MongolTextField's
  /// value: when they have inserted or deleted text.
  ///
  /// This callback doesn't run when the MongolTextField's text is changed
  /// programmatically, via the MongolTextField's [controller]. Typically it
  /// isn't necessary to be notified of such changes, since they're
  /// initiated by the app itself.
  ///
  /// To be notified of all changes to the MongolTextField's text, cursor,
  /// and selection, one can add a listener to its [controller] with
  /// [TextEditingController.addListener].
  ///
  /// ## Handling emojis and other complex characters
  ///
  /// It's important to always use
  /// [characters](https://pub.dev/packages/characters) when dealing with user
  /// input text that may contain complex characters. This will ensure that
  /// extended grapheme clusters and surrogate pairs are treated as single
  /// characters, as they appear to the user.
  ///
  /// For example, when finding the length of some user input, use
  /// `string.characters.length`. Do NOT use `string.length` or even
  /// `string.runes.length`. For the complex character "👨‍👩‍👦", this
  /// appears to the user as a single character, and `string.characters.length`
  /// intuitively returns 1. On the other hand, `string.length` returns 8, and
  /// `string.runes.length` returns 5!
  ///
  /// See also:
  ///
  ///  * [inputFormatters], which are called before [onChanged]
  ///    runs and can validate and change ("format") the input value.
  ///  * [onEditingComplete], [onSubmitted], [onSelectionChanged]:
  ///    which are more specialized input change notifications.
  final ValueChanged<String>? onChanged;

  /// Called when the user submits editable content (e.g., user presses the "done"
  /// button on the keyboard).
  ///
  /// The default implementation of [onEditingComplete] executes 2 different
  /// behaviors based on the situation:
  ///
  ///  - When a completion action is pressed, such as "done", "go", "send", or
  ///    "search", the user's content is submitted to the [controller] and then
  ///    focus is given up.
  ///
  ///  - When a non-completion action is pressed, such as "next" or "previous",
  ///    the user's content is submitted to the [controller], but focus is not
  ///    given up because developers may want to immediately move focus to
  ///    another input widget within [onSubmitted].
  ///
  /// Providing [onEditingComplete] prevents the aforementioned default behavior.
  final VoidCallback? onEditingComplete;

  /// Called when the user indicates that they are done editing the text in the
  /// field.
  final ValueChanged<String>? onSubmitted;

  /// This is used to receive a private command from the input method.
  ///
  /// Called when the result of [TextInputClient.performPrivateCommand] is
  /// received.
  ///
  /// This can be used to provide domain-specific features that are only known
  /// between certain input methods and their clients.
  ///
  /// See also:
  ///   * [https://developer.android.com/reference/android/view/inputmethod/InputConnection#performPrivateCommand(java.lang.String,%20android.os.Bundle)],
  ///     which is the Android documentation for performPrivateCommand, used to
  ///     send a command from the input method.
  ///   * [https://developer.android.com/reference/android/view/inputmethod/InputMethodManager#sendAppPrivateCommand],
  ///     which is the Android documentation for sendAppPrivateCommand, used to
  ///     send a command to the input method.
  final AppPrivateCommandCallback? onAppPrivateCommand;

  /// Called when the user changes the selection of text (including the cursor
  /// location).
  final SelectionChangedCallback? onSelectionChanged;

  /// A callback that's invoked when a selection handle is tapped.
  ///
  /// Both regular taps and long presses invoke this callback, but a drag
  /// gesture won't.
  final VoidCallback? onSelectionHandleTapped;

  /// Optional input validation and formatting overrides.
  ///
  /// Formatters are run in the provided order when the text input changes. When
  /// this parameter changes, the new formatters will not be applied until the
  /// next time the user inserts or deletes text.
  final List<TextInputFormatter>? inputFormatters;

  /// The cursor for a mouse pointer when it enters or is hovering over the
  /// widget.
  ///
  /// If this property is null, [SystemMouseCursors.text] will be used.
  ///
  /// The [mouseCursor] is the only property of [MongolEditableText] that controls the
  /// appearance of the mouse pointer. All other properties related to "cursor"
  /// stands for the text cursor, which is usually a blinking vertical line at
  /// the editing position.
  final MouseCursor? mouseCursor;

  /// If true, the [MongolRenderEditable] created by this widget will not handle
  /// pointer events, see [MongolRenderEditable] and
  /// [MongolRenderEditable.ignorePointer].
  ///
  /// This property is false by default.
  final bool rendererIgnoresPointer;

  /// How wide the cursor will be.
  ///
  /// If this property is null, [MongolRenderEditable.preferredLineWidth] will
  /// be used.
  final double? cursorWidth;

  /// How thick the cursor will be.
  ///
  /// Defaults to 2.0.
  ///
  /// The cursor will draw above the text. The cursor height will extend
  /// down from the boundary between characters. This corresponds to extending
  /// downstream relative to the selected position. Negative values may be used
  /// to reverse this behavior.
  final double cursorHeight;

  /// How rounded the corners of the cursor should be.
  ///
  /// By default, the cursor has no radius.
  final Radius? cursorRadius;

  /// Whether the cursor will animate from fully transparent to fully opaque
  /// during each cursor blink.
  ///
  /// By default, the cursor opacity will animate on iOS platforms and will not
  /// animate on Android platforms.
  final bool cursorOpacityAnimates;

  /// The offset that is used, in pixels, when painting the cursor on screen.
  ///
  /// By default, the cursor position should be set to an offset of
  /// (0.0, -[cursorHeight] * 0.5) on iOS platforms and (0, 0) on Android
  /// platforms. The origin from where the offset is applied to is the arbitrary
  /// location where the cursor ends up being rendered from by default.
  final Offset? cursorOffset;

  /// The appearance of the keyboard.
  ///
  /// This setting is only honored on iOS devices.
  ///
  /// Defaults to [Brightness.light].
  final Brightness keyboardAppearance;

  /// Configures padding to edges surrounding a [Scrollable] when the
  /// MongolTextField scrolls into view.
  ///
  /// When this widget receives focus and is not completely visible (for
  /// example scrolled partially off the screen or overlapped by the keyboard)
  /// then it will attempt to make itself visible by scrolling a surrounding
  /// [Scrollable], if one is present. This value controls how far from the
  /// edges of a [Scrollable] the MongolTextField will be positioned after the
  /// scroll.
  ///
  /// Defaults to EdgeInsets.all(20.0).
  final EdgeInsets scrollPadding;

  /// Whether to enable user interface affordances for changing the
  /// text selection.
  ///
  /// For example, setting this to true will enable features such as
  /// long-pressing the MongolTextField to select text and show the
  /// cut/copy/paste menu, and tapping to move the text caret.
  ///
  /// When this is false, the text selection cannot be adjusted by
  /// the user, text cannot be copied, and the user cannot paste into
  /// the text field from the clipboard.
  final bool enableInteractiveSelection;

  /// Setting this property to true makes the cursor stop blinking or fading
  /// on and off once the cursor appears on focus. This property is useful for
  /// testing purposes.
  ///
  /// It does not affect the necessity to focus the EditableText for the cursor
  /// to appear in the first place.
  ///
  /// Defaults to false, resulting in a typical blinking cursor.
  static bool debugDeterministicCursor = false;

  /// Determines the way that drag start behavior is handled.
  ///
  /// If set to [DragStartBehavior.start], scrolling drag behavior will
  /// begin upon the detection of a drag gesture. If set to
  /// [DragStartBehavior.down] it will begin when a down event is first detected.
  ///
  /// In general, setting this to [DragStartBehavior.start] will make drag
  /// animation smoother and setting it to [DragStartBehavior.down] will make
  /// drag behavior feel slightly more reactive.
  ///
  /// By default, the drag start behavior is [DragStartBehavior.start].
  ///
  /// See also:
  ///
  ///  * [DragGestureRecognizer.dragStartBehavior], which gives an example for
  ///    the different behaviors.
  final DragStartBehavior dragStartBehavior;

  /// The [ScrollController] to use when horizontally scrolling the input.
  ///
  /// If null, it will instantiate a new ScrollController.
  ///
  /// See [Scrollable.controller].
  final ScrollController? scrollController;

  /// The [ScrollPhysics] to use when horizontally scrolling the input.
  ///
  /// If not specified, it will behave according to the current platform.
  ///
  /// See [Scrollable.physics].
  ///
  /// If an explicit [ScrollBehavior] is provided to [scrollBehavior], the
  /// [ScrollPhysics] provided by that behavior will take precedence after
  /// [scrollPhysics].
  final ScrollPhysics? scrollPhysics;

  /// Same as [enableInteractiveSelection].
  ///
  /// This getter exists primarily for consistency with
  /// [MongolRenderEditable.selectionEnabled].
  bool get selectionEnabled => enableInteractiveSelection;

  /// A list of strings that helps the autofill service identify the type of this
  /// text input.
  ///
  /// When set to null or empty, this text input will not send its autofill
  /// information to the platform, preventing it from participating in
  /// autofills triggered by a different [AutofillClient], even if they're in the
  /// same [AutofillScope]. Additionally, on Android and web, setting this to
  /// null or empty will disable autofill for this text field.
  ///
  /// The minimum platform SDK version that supports Autofill is API level 26
  /// for Android, and iOS 10.0 for iOS.
  ///
  /// ### Setting up iOS autofill:
  ///
  /// To provide the best user experience and ensure your app fully supports
  /// password autofill on iOS, follow these steps:
  ///
  /// * Set up your iOS app's
  ///   [associated domains](https://developer.apple.com/documentation/safariservices/supporting_associated_domains_in_your_app).
  /// * Some autofill hints only work with specific [keyboardType]s. For example,
  ///   [AutofillHints.name] requires [TextInputType.name] and [AutofillHints.email]
  ///   works only with [TextInputType.emailAddress]. Make sure the input field has a
  ///   compatible [keyboardType]. Empirically, [TextInputType.name] works well
  ///   with many autofill hints that are predefined on iOS.
  ///
  /// ### Troubleshooting Autofill
  ///
  /// Autofill service providers rely heavily on [autofillHints]. Make sure the
  /// entries in [autofillHints] are supported by the autofill service currently
  /// in use (the name of the service can typically be found in your mobile
  /// device's system settings).
  ///
  /// #### Autofill UI refuses to show up when I tap on the text field
  ///
  /// Check the device's system settings and make sure autofill is turned on,
  /// and there're available credentials stored in the autofill service.
  ///
  /// * iOS password autofill: Go to Settings -> Password, turn on "Autofill
  ///   Passwords", and add new passwords for testing by pressing the top right
  ///   "+" button. Use an arbitrary "website" if you don't have associated
  ///   domains set up for your app. As long as there's at least one password
  ///   stored, you should be able to see a key-shaped icon in the quick type
  ///   bar on the software keyboard, when a password related field is focused.
  ///
  /// * iOS contact information autofill: iOS seems to pull contact info from
  ///   the Apple ID currently associated with the device. Go to Settings ->
  ///   Apple ID (usually the first entry, or "Sign in to your iPhone" if you
  ///   haven't set up one on the device), and fill out the relevant fields. If
  ///   you wish to test more contact info types, try adding them in Contacts ->
  ///   My Card.
  ///
  /// * Android autofill: Go to Settings -> System -> Languages & input ->
  ///   Autofill service. Enable the autofill service of your choice, and make
  ///   sure there're available credentials associated with your app.
  ///
  /// #### I called `TextInput.finishAutofillContext` but the autofill save
  /// prompt isn't showing
  ///
  /// * iOS: iOS may not show a prompt or any other visual indication when it
  ///   saves user password. Go to Settings -> Password and check if your new
  ///   password is saved. Neither saving password nor auto-generating strong
  ///   password works without properly setting up associated domains in your
  ///   app. To set up associated domains, follow the instructions in
  ///   <https://developer.apple.com/documentation/safariservices/supporting_associated_domains_in_your_app>.
  final Iterable<String>? autofillHints;

  /// The [AutofillClient] that controls this input field's autofill behavior.
  ///
  /// When null, this widget's [MongolEditableTextState] will be used as the
  /// [AutofillClient]. This property may override [autofillHints].
  final AutofillClient? autofillClient;

  /// The content will be clipped (or not) according to this option.
  ///
  /// See the enum [Clip] for details of all possible options and their common
  /// use cases.
  ///
  /// Defaults to [Clip.hardEdge].
  final Clip clipBehavior;

  /// Restoration ID to save and restore the scroll offset of the
  /// [MongolEditableText].
  ///
  /// If a restoration id is provided, the [MongolEditableText] will persist its
  /// current scroll offset and restore it during state restoration.
  ///
  /// The scroll offset is persisted in a [RestorationBucket] claimed from
  /// the surrounding [RestorationScope] using the provided restoration ID.
  ///
  /// Persisting and restoring the content of the [MongolEditableText] is the
  /// responsibility of the owner of the [controller], who may use a
  /// [RestorableTextEditingController] for that purpose.
  ///
  /// See also:
  ///
  ///  * [RestorationManager], which explains how state restoration works in
  ///    Flutter.
  final String? restorationId;

  /// A [ScrollBehavior] that will be applied to this widget individually.
  ///
  /// Defaults to null, wherein the inherited [ScrollBehavior] is copied and
  /// modified to alter the viewport decoration, like [Scrollbar]s.
  ///
  /// [ScrollBehavior]s also provide [ScrollPhysics]. If an explicit
  /// [ScrollPhysics] is provided in [scrollPhysics], it will take precedence,
  /// followed by [scrollBehavior], and then the inherited ancestor
  /// [ScrollBehavior].
  ///
  /// The [ScrollBehavior] of the inherited [ScrollConfiguration] will be
  /// modified by default to only apply a [Scrollbar] if [maxLines] is greater
  /// than 1.
  final ScrollBehavior? scrollBehavior;

  // Infer the keyboard type of a `MongolEditableText` if it's not specified.
  static TextInputType _inferKeyboardType({
    required Iterable<String>? autofillHints,
    required int? maxLines,
  }) {
    if (autofillHints?.isEmpty ?? true) {
      return maxLines == 1 ? TextInputType.text : TextInputType.multiline;
    }

    TextInputType? returnValue;
    final effectiveHint = autofillHints!.first;

    // On iOS oftentimes specifying a text content type is not enough to qualify
    // the input field for autofill. The keyboard type also needs to be compatible
    // with the content type. To get autofill to work by default on MongolEditableText,
    // the keyboard type inference on iOS is done differently from other platforms.
    //
    // The entries with "autofill not working" comments are the iOS text content
    // types that should work with the specified keyboard type but won't trigger
    // (even within a native app). Tested on iOS 13.5.
    if (!kIsWeb) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          const Map<String, TextInputType> iOSKeyboardType =
              <String, TextInputType>{
            AutofillHints.addressCity: TextInputType.name,
            AutofillHints.addressCityAndState:
                TextInputType.name, // Autofill not working.
            AutofillHints.addressState: TextInputType.name,
            AutofillHints.countryName: TextInputType.name,
            AutofillHints.creditCardNumber:
                TextInputType.number, // Couldn't test.
            AutofillHints.email: TextInputType.emailAddress,
            AutofillHints.familyName: TextInputType.name,
            AutofillHints.fullStreetAddress: TextInputType.name,
            AutofillHints.givenName: TextInputType.name,
            AutofillHints.jobTitle: TextInputType.name, // Autofill not working.
            AutofillHints.location: TextInputType.name, // Autofill not working.
            AutofillHints.middleName:
                TextInputType.name, // Autofill not working.
            AutofillHints.name: TextInputType.name,
            AutofillHints.namePrefix:
                TextInputType.name, // Autofill not working.
            AutofillHints.nameSuffix:
                TextInputType.name, // Autofill not working.
            AutofillHints.newPassword: TextInputType.text,
            AutofillHints.newUsername: TextInputType.text,
            AutofillHints.nickname: TextInputType.name, // Autofill not working.
            AutofillHints.oneTimeCode: TextInputType.number,
            AutofillHints.organizationName:
                TextInputType.text, // Autofill not working.
            AutofillHints.password: TextInputType.text,
            AutofillHints.postalCode: TextInputType.name,
            AutofillHints.streetAddressLine1: TextInputType.name,
            AutofillHints.streetAddressLine2:
                TextInputType.name, // Autofill not working.
            AutofillHints.sublocality:
                TextInputType.name, // Autofill not working.
            AutofillHints.telephoneNumber: TextInputType.name,
            AutofillHints.url: TextInputType.url, // Autofill not working.
            AutofillHints.username: TextInputType.text,
          };

          returnValue = iOSKeyboardType[effectiveHint];
          break;
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          break;
      }
    }

    if (returnValue != null || maxLines != 1) {
      return returnValue ?? TextInputType.multiline;
    }

    const inferKeyboardType = <String, TextInputType>{
      AutofillHints.addressCity: TextInputType.streetAddress,
      AutofillHints.addressCityAndState: TextInputType.streetAddress,
      AutofillHints.addressState: TextInputType.streetAddress,
      AutofillHints.birthday: TextInputType.datetime,
      AutofillHints.birthdayDay: TextInputType.datetime,
      AutofillHints.birthdayMonth: TextInputType.datetime,
      AutofillHints.birthdayYear: TextInputType.datetime,
      AutofillHints.countryCode: TextInputType.number,
      AutofillHints.countryName: TextInputType.text,
      AutofillHints.creditCardExpirationDate: TextInputType.datetime,
      AutofillHints.creditCardExpirationDay: TextInputType.datetime,
      AutofillHints.creditCardExpirationMonth: TextInputType.datetime,
      AutofillHints.creditCardExpirationYear: TextInputType.datetime,
      AutofillHints.creditCardFamilyName: TextInputType.name,
      AutofillHints.creditCardGivenName: TextInputType.name,
      AutofillHints.creditCardMiddleName: TextInputType.name,
      AutofillHints.creditCardName: TextInputType.name,
      AutofillHints.creditCardNumber: TextInputType.number,
      AutofillHints.creditCardSecurityCode: TextInputType.number,
      AutofillHints.creditCardType: TextInputType.text,
      AutofillHints.email: TextInputType.emailAddress,
      AutofillHints.familyName: TextInputType.name,
      AutofillHints.fullStreetAddress: TextInputType.streetAddress,
      AutofillHints.gender: TextInputType.text,
      AutofillHints.givenName: TextInputType.name,
      AutofillHints.impp: TextInputType.url,
      AutofillHints.jobTitle: TextInputType.text,
      AutofillHints.language: TextInputType.text,
      AutofillHints.location: TextInputType.streetAddress,
      AutofillHints.middleInitial: TextInputType.name,
      AutofillHints.middleName: TextInputType.name,
      AutofillHints.name: TextInputType.name,
      AutofillHints.namePrefix: TextInputType.name,
      AutofillHints.nameSuffix: TextInputType.name,
      AutofillHints.newPassword: TextInputType.text,
      AutofillHints.newUsername: TextInputType.text,
      AutofillHints.nickname: TextInputType.text,
      AutofillHints.oneTimeCode: TextInputType.text,
      AutofillHints.organizationName: TextInputType.text,
      AutofillHints.password: TextInputType.text,
      AutofillHints.photo: TextInputType.text,
      AutofillHints.postalAddress: TextInputType.streetAddress,
      AutofillHints.postalAddressExtended: TextInputType.streetAddress,
      AutofillHints.postalAddressExtendedPostalCode: TextInputType.number,
      AutofillHints.postalCode: TextInputType.number,
      AutofillHints.streetAddressLevel1: TextInputType.streetAddress,
      AutofillHints.streetAddressLevel2: TextInputType.streetAddress,
      AutofillHints.streetAddressLevel3: TextInputType.streetAddress,
      AutofillHints.streetAddressLevel4: TextInputType.streetAddress,
      AutofillHints.streetAddressLine1: TextInputType.streetAddress,
      AutofillHints.streetAddressLine2: TextInputType.streetAddress,
      AutofillHints.streetAddressLine3: TextInputType.streetAddress,
      AutofillHints.sublocality: TextInputType.streetAddress,
      AutofillHints.telephoneNumber: TextInputType.phone,
      AutofillHints.telephoneNumberAreaCode: TextInputType.phone,
      AutofillHints.telephoneNumberCountryCode: TextInputType.phone,
      AutofillHints.telephoneNumberDevice: TextInputType.phone,
      AutofillHints.telephoneNumberExtension: TextInputType.phone,
      AutofillHints.telephoneNumberLocal: TextInputType.phone,
      AutofillHints.telephoneNumberLocalPrefix: TextInputType.phone,
      AutofillHints.telephoneNumberLocalSuffix: TextInputType.phone,
      AutofillHints.telephoneNumberNational: TextInputType.phone,
      AutofillHints.transactionAmount:
          TextInputType.numberWithOptions(decimal: true),
      AutofillHints.transactionCurrency: TextInputType.text,
      AutofillHints.url: TextInputType.url,
      AutofillHints.username: TextInputType.text,
    };

    return inferKeyboardType[effectiveHint] ?? TextInputType.text;
  }

  @override
  MongolEditableTextState createState() => MongolEditableTextState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
        DiagnosticsProperty<TextEditingController>('controller', controller));
    properties.add(DiagnosticsProperty<FocusNode>('focusNode', focusNode));
    properties.add(DiagnosticsProperty<bool>('obscureText', obscureText,
        defaultValue: false));
    properties.add(DiagnosticsProperty<bool>('autocorrect', autocorrect,
        defaultValue: true));
    properties.add(DiagnosticsProperty<bool>(
        'enableSuggestions', enableSuggestions,
        defaultValue: true));
    style.debugFillProperties(properties);
    properties.add(EnumProperty<MongolTextAlign>('textAlign', textAlign,
        defaultValue: null));
    properties.add(
        DoubleProperty('textScaleFactor', textScaleFactor, defaultValue: null));
    properties.add(IntProperty('maxLines', maxLines, defaultValue: 1));
    properties.add(IntProperty('minLines', minLines, defaultValue: null));
    properties.add(
        DiagnosticsProperty<bool>('expands', expands, defaultValue: false));
    properties.add(
        DiagnosticsProperty<bool>('autofocus', autofocus, defaultValue: false));
    properties.add(DiagnosticsProperty<TextInputType>(
        'keyboardType', keyboardType,
        defaultValue: null));
    properties.add(DiagnosticsProperty<ScrollController>(
        'scrollController', scrollController,
        defaultValue: null));
    properties.add(DiagnosticsProperty<ScrollPhysics>(
        'scrollPhysics', scrollPhysics,
        defaultValue: null));
    properties.add(DiagnosticsProperty<Iterable<String>>(
        'autofillHints', autofillHints,
        defaultValue: null));
  }
}

/// State for a [MongolEditableText].
class MongolEditableTextState extends State<MongolEditableText>
    with
        AutomaticKeepAliveClientMixin<MongolEditableText>,
        WidgetsBindingObserver,
        TickerProviderStateMixin<MongolEditableText>,
        TextSelectionDelegate
    implements TextInputClient, AutofillClient, MongolTextEditingActionTarget {
  Timer? _cursorTimer;
  bool _targetCursorVisibility = false;
  final ValueNotifier<bool> _cursorVisibilityNotifier =
      ValueNotifier<bool>(true);
  final GlobalKey _editableKey = GlobalKey();
  final ClipboardStatusNotifier? _clipboardStatus =
      kIsWeb ? null : ClipboardStatusNotifier();

  TextInputConnection? _textInputConnection;
  MongolTextSelectionOverlay? _selectionOverlay;

  ScrollController? _scrollController;

  late AnimationController _cursorBlinkOpacityController;

  final LayerLink _toolbarLayerLink = LayerLink();
  final LayerLink _startHandleLayerLink = LayerLink();
  final LayerLink _endHandleLayerLink = LayerLink();

  bool _didAutoFocus = false;
  FocusAttachment? _focusAttachment;

  AutofillGroupState? _currentAutofillScope;

  @override
  AutofillScope? get currentAutofillScope => _currentAutofillScope;

  AutofillClient get _effectiveAutofillClient => widget.autofillClient ?? this;

  // Is this field in the current autofill context.
  bool _isInAutofillContext = false;

  /// Whether to create an input connection with the platform for text editing
  /// or not.
  ///
  /// Read-only input fields do not need a connection with the platform since
  /// there's no need for text editing capabilities (e.g. virtual keyboard).
  ///
  /// On the web, we always need a connection because we want some browser
  /// functionalities to continue to work on read-only input fields like:
  ///
  /// - Relevant context menu.
  /// - cmd/ctrl+c shortcut to copy.
  /// - cmd/ctrl+a to select all.
  /// - Changing the selection using a physical keyboard.
  bool get _shouldCreateInputConnection => kIsWeb || !widget.readOnly;

  // This value is an eyeball estimation of the time it takes for the iOS cursor
  // to ease in and out.
  static const Duration _fadeDuration = Duration(milliseconds: 250);

  @override
  bool get wantKeepAlive => widget.focusNode.hasFocus;

  Color get _cursorColor =>
      widget.cursorColor.withOpacity(_cursorBlinkOpacityController.value);

  @override
  bool get cutEnabled => widget.toolbarOptions.cut && !widget.readOnly;

  @override
  bool get copyEnabled => widget.toolbarOptions.copy;

  @override
  bool get pasteEnabled => widget.toolbarOptions.paste && !widget.readOnly;

  @override
  bool get selectAllEnabled => widget.toolbarOptions.selectAll;

  void _onChangedClipboardStatus() {
    setState(() {
      // Inform the widget that the value of clipboardStatus has changed.
    });
  }

  TextEditingValue get _textEditingValueForTextLayoutMetrics {
    final Widget? editableWidget = _editableKey.currentContext?.widget;
    if (editableWidget is! _MongolEditable) {
      throw StateError('_Editable must be mounted.');
    }
    return editableWidget.value;
  }

  // todo editor-fixes copy from [EditableTextState]
  /// Copy current selection to [Clipboard].
  @override
  void copySelection(SelectionChangedCause cause) {
    final TextSelection selection = textEditingValue.selection;
    if (selection.isCollapsed || widget.obscureText) {
      return;
    }
    final String text = textEditingValue.text;
    Clipboard.setData(ClipboardData(text: selection.textInside(text)));
    if (cause == SelectionChangedCause.toolbar) {
      bringIntoView(textEditingValue.selection.extent);
      hideToolbar(false);

      switch (defaultTargetPlatform) {
        case TargetPlatform.iOS:
          break;
        case TargetPlatform.macOS:
        case TargetPlatform.android:
        case TargetPlatform.fuchsia:
        case TargetPlatform.linux:
        case TargetPlatform.windows:
          // Collapse the selection and hide the toolbar and handles.
          userUpdateTextEditingValue(
            TextEditingValue(
              text: textEditingValue.text,
              selection: TextSelection.collapsed(
                  offset: textEditingValue.selection.end),
            ),
            SelectionChangedCause.toolbar,
          );
          break;
      }
    }
    _clipboardStatus?.update();
  }

  // todo editor-fixes copy from [EditableTextState]
  /// Cut current selection to [Clipboard].
  @override
  void cutSelection(SelectionChangedCause cause) {
    if (widget.readOnly || widget.obscureText) {
      return;
    }
    final TextSelection selection = textEditingValue.selection;
    final String text = textEditingValue.text;
    if (selection.isCollapsed) {
      return;
    }
    Clipboard.setData(ClipboardData(text: selection.textInside(text)));
    _replaceText(ReplaceTextIntent(textEditingValue, '', selection, cause));
    if (cause == SelectionChangedCause.toolbar) {
      // Schedule a call to bringIntoView() after renderEditable updates.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          bringIntoView(textEditingValue.selection.extent);
        }
      });
      hideToolbar();
    }
    _clipboardStatus?.update();
  }

  // todo editor-fixes copy from [EditableTextState]
  /// Paste text from [Clipboard].
  @override
  Future<void> pasteText(SelectionChangedCause cause) async {
    if (widget.readOnly) {
      return;
    }
    final TextSelection selection = textEditingValue.selection;
    if (!selection.isValid) {
      return;
    }
    // Snapshot the input before using `await`.
    // See https://github.com/flutter/flutter/issues/11427
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data == null) {
      return;
    }

    // After the paste, the cursor should be collapsed and located after the
    // pasted content.
    final int lastSelectionIndex =
        math.max(selection.baseOffset, selection.extentOffset);
    final TextEditingValue collapsedTextEditingValue =
        textEditingValue.copyWith(
      selection: TextSelection.collapsed(offset: lastSelectionIndex),
    );

    userUpdateTextEditingValue(
      collapsedTextEditingValue.replaced(selection, data.text!),
      cause,
    );
    if (cause == SelectionChangedCause.toolbar) {
      // Schedule a call to bringIntoView() after renderEditable updates.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          bringIntoView(textEditingValue.selection.extent);
        }
      });
      hideToolbar();
    }
  }

  // todo editor-fixes copy from [EditableTextState]
  /// Select the entire text value.
  @override
  void selectAll(SelectionChangedCause cause) {
    if (widget.readOnly && widget.obscureText) {
      // If we can't modify it, and we can't copy it, there's no point in
      // selecting it.
      return;
    }
    userUpdateTextEditingValue(
      textEditingValue.copyWith(
        selection: TextSelection(
            baseOffset: 0, extentOffset: textEditingValue.text.length),
      ),
      cause,
    );
    if (cause == SelectionChangedCause.toolbar) {
      bringIntoView(textEditingValue.selection.extent);
    }
  }

  // todo editor-fixes copy from [EditableTextState]
  @override
  void autofill(TextEditingValue value) => updateEditingValue(value);

  @override
  void insertTextPlaceholder(Size size) {
    // todo editor-fixes should we implement it?
  }

  @override
  void removeTextPlaceholder() {
    // todo editor-fixes should we implement it?
  }
  // State lifecycle:

  @override
  void initState() {
    super.initState();
    _clipboardStatus?.addListener(_onChangedClipboardStatus);
    widget.controller.addListener(_didChangeTextEditingValue);
    _focusAttachment = widget.focusNode.attach(context);
    widget.focusNode.addListener(_handleFocusChanged);
    _scrollController = widget.scrollController ?? ScrollController();
    _scrollController!.addListener(() {
      _selectionOverlay?.updateForScroll();
    });
    _cursorBlinkOpacityController =
        AnimationController(vsync: this, duration: _fadeDuration);
    _cursorBlinkOpacityController.addListener(_onCursorColorTick);
    _cursorVisibilityNotifier.value = widget.showCursor;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newAutofillGroup = AutofillGroup.of(context);
    if (currentAutofillScope != newAutofillGroup) {
      _currentAutofillScope?.unregister(autofillId);
      _currentAutofillScope = newAutofillGroup;
      newAutofillGroup?.register(this);
      _isInAutofillContext = _isInAutofillContext || _shouldBeInAutofillContext;
    }

    if (!_didAutoFocus && widget.autofocus) {
      _didAutoFocus = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).autofocus(widget.focusNode);
        }
      });
    }
  }

  @override
  void didUpdateWidget(MongolEditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller.removeListener(_didChangeTextEditingValue);
      widget.controller.addListener(_didChangeTextEditingValue);
      _updateRemoteEditingValueIfNeeded();
    }
    if (widget.controller.selection != oldWidget.controller.selection) {
      _selectionOverlay?.update(_value);
    }
    _selectionOverlay?.handlesVisible = widget.showSelectionHandles;
    _isInAutofillContext = _isInAutofillContext || _shouldBeInAutofillContext;

    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChanged);
      _focusAttachment?.detach();
      _focusAttachment = widget.focusNode.attach(context);
      widget.focusNode.addListener(_handleFocusChanged);
      updateKeepAlive();
    }

    if (!_shouldCreateInputConnection) {
      _closeInputConnectionIfNeeded();
    } else if (oldWidget.readOnly && _hasFocus) {
      _openInputConnection();
    }

    if (kIsWeb && _hasInputConnection) {
      if (oldWidget.readOnly != widget.readOnly) {
        _textInputConnection!.updateConfig(textInputConfiguration);
      }
    }

    if (widget.style != oldWidget.style) {
      final style = widget.style;
      // The _textInputConnection will pick up the new style when it attaches in
      // _openInputConnection.
      if (_hasInputConnection) {
        _textInputConnection!.setStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          textDirection: TextDirection.ltr,
          textAlign: _rotatedTextAlign(widget.textAlign),
        );
      }
    }
    if (widget.selectionEnabled &&
        pasteEnabled &&
        widget.selectionControls?.canPaste(this) == true) {
      _clipboardStatus?.update();
    }
  }

  TextAlign _rotatedTextAlign(MongolTextAlign mongolTextAlign) {
    switch (mongolTextAlign) {
      case MongolTextAlign.top:
        return TextAlign.left;
      case MongolTextAlign.center:
        return ui.TextAlign.center;
      case MongolTextAlign.bottom:
        return TextAlign.right;
      case MongolTextAlign.justify:
        return TextAlign.justify;
    }
  }

  @override
  void dispose() {
    _currentAutofillScope?.unregister(autofillId);
    widget.controller.removeListener(_didChangeTextEditingValue);
    _cursorBlinkOpacityController.removeListener(_onCursorColorTick);
    _closeInputConnectionIfNeeded();
    assert(!_hasInputConnection);
    _stopCursorTimer();
    assert(_cursorTimer == null);
    _selectionOverlay?.dispose();
    _selectionOverlay = null;
    _focusAttachment!.detach();
    widget.focusNode.removeListener(_handleFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    _clipboardStatus?.removeListener(_onChangedClipboardStatus);
    _clipboardStatus?.dispose();
    super.dispose();
    assert(_batchEditDepth <= 0, 'unfinished batch edits: $_batchEditDepth');
  }

  // TextInputClient implementation:

  /// The last known [TextEditingValue] of the platform text input plugin.
  ///
  /// This value is updated when the platform text input plugin sends a new
  /// update via [updateEditingValue], or when [MongolEditableText] calls
  /// [TextInputConnection.setEditingState] to overwrite the platform text input
  /// plugin's [TextEditingValue].
  ///
  /// Used in [_updateRemoteEditingValueIfNeeded] to determine whether the
  /// remote value is outdated and needs updating.
  TextEditingValue? _lastKnownRemoteTextEditingValue;

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  void updateEditingValue(TextEditingValue value) {
    // This method handles text editing state updates from the platform text
    // input plugin. The [MongolEditableText] may not have the focus or an open input
    // connection, as autofill can update a disconnected [MongolEditableText].

    // Since we still have to support keyboard select, this is the best place
    // to disable text updating.
    if (!_shouldCreateInputConnection) {
      return;
    }

    if (widget.readOnly) {
      // In the read-only case, we only care about selection changes, and reject
      // everything else.
      value = _value.copyWith(selection: value.selection);
    }
    _lastKnownRemoteTextEditingValue = value;

    if (value == _value) {
      // This is possible, for example, when the numeric keyboard is input,
      // the engine will notify twice for the same value.
      // Track at https://github.com/flutter/flutter/issues/65811
      return;
    }

    if (value.text == _value.text && value.composing == _value.composing) {
      // `selection` is the only change.
      _handleSelectionChanged(value.selection, SelectionChangedCause.keyboard);
    } else {
      hideToolbar();

      if (_hasInputConnection) {
        if (widget.obscureText && value.text.length == _value.text.length + 1) {
          _obscureShowCharTicksPending = _kObscureShowLatestCharCursorTicks;
          _obscureLatestCharIndex = _value.selection.baseOffset;
        }
      }

      _formatAndSetValue(value, SelectionChangedCause.keyboard);
    }

    // Wherever the value is changed by the user, schedule a showCaretOnScreen
    // to make sure the user can see the changes they just made. Programmatical
    // changes to `textEditingValue` do not trigger the behavior even if the
    // text field is focused.
    _scheduleShowCaretOnScreen();
    if (_hasInputConnection) {
      // To keep the cursor from blinking while typing, we want to restart the
      // cursor timer every time a new character is typed.
      _stopCursorTimer(resetCharTicks: false);
      _startCursorTimer();
    }
  }

  @override
  void performAction(TextInputAction action) {
    switch (action) {
      case TextInputAction.newline:
        // If this is a multiline EditableText, do nothing for a "newline"
        // action; The newline is already inserted. Otherwise, finalize
        // editing.
        if (!_isMultiline) _finalizeEditing(action, shouldUnfocus: true);
        break;
      case TextInputAction.done:
      case TextInputAction.go:
      case TextInputAction.next:
      case TextInputAction.previous:
      case TextInputAction.search:
      case TextInputAction.send:
        _finalizeEditing(action, shouldUnfocus: true);
        break;
      case TextInputAction.continueAction:
      case TextInputAction.emergencyCall:
      case TextInputAction.join:
      case TextInputAction.none:
      case TextInputAction.route:
      case TextInputAction.unspecified:
        // Finalize editing, but don't give up focus because this keyboard
        // action does not imply the user is done inputting information.
        _finalizeEditing(action, shouldUnfocus: false);
        break;
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    widget.onAppPrivateCommand!(action, data);
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    // unimplemented
  }

  @pragma('vm:notify-debugger-on-exception')
  void _finalizeEditing(TextInputAction action, {required bool shouldUnfocus}) {
    // Take any actions necessary now that the user has completed editing.
    if (widget.onEditingComplete != null) {
      try {
        widget.onEditingComplete!();
      } catch (exception, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'widgets',
          context:
              ErrorDescription('while calling onEditingComplete for $action'),
        ));
      }
    } else {
      // Default behavior if the developer did not provide an
      // onEditingComplete callback: Finalize editing and remove focus, or move
      // it to the next/previous field, depending on the action.
      widget.controller.clearComposing();
      if (shouldUnfocus) {
        switch (action) {
          case TextInputAction.none:
          case TextInputAction.unspecified:
          case TextInputAction.done:
          case TextInputAction.go:
          case TextInputAction.search:
          case TextInputAction.send:
          case TextInputAction.continueAction:
          case TextInputAction.join:
          case TextInputAction.route:
          case TextInputAction.emergencyCall:
          case TextInputAction.newline:
            widget.focusNode.unfocus();
            break;
          case TextInputAction.next:
            widget.focusNode.nextFocus();
            break;
          case TextInputAction.previous:
            widget.focusNode.previousFocus();
            break;
        }
      }
    }

    // Invoke optional callback with the user's submitted content.
    try {
      widget.onSubmitted?.call(_value.text);
    } catch (exception, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'widgets',
        context: ErrorDescription('while calling onSubmitted for $action'),
      ));
    }
  }

  int _batchEditDepth = 0;

  /// Begins a new batch edit, within which new updates made to the text editing
  /// value will not be sent to the platform text input plugin.
  ///
  /// Batch edits nest. When the outermost batch edit finishes, [endBatchEdit]
  /// will attempt to send [currentTextEditingValue] to the text input plugin if
  /// it detected a change.
  void beginBatchEdit() {
    _batchEditDepth += 1;
  }

  /// Ends the current batch edit started by the last call to [beginBatchEdit],
  /// and send [currentTextEditingValue] to the text input plugin if needed.
  ///
  /// Throws an error in debug mode if this [EditableText] is not in a batch
  /// edit.
  void endBatchEdit() {
    _batchEditDepth -= 1;
    assert(
      _batchEditDepth >= 0,
      'Unbalanced call to endBatchEdit: beginBatchEdit must be called first.',
    );
    _updateRemoteEditingValueIfNeeded();
  }

  void _updateRemoteEditingValueIfNeeded() {
    if (_batchEditDepth > 0 || !_hasInputConnection) return;
    final localValue = _value;
    if (localValue == _lastKnownRemoteTextEditingValue) return;
    _textInputConnection!.setEditingState(localValue);
    _lastKnownRemoteTextEditingValue = localValue;
  }

  TextEditingValue get _value => widget.controller.value;

  set _value(TextEditingValue value) {
    widget.controller.value = value;
  }

  bool get _hasFocus => widget.focusNode.hasFocus;

  bool get _isMultiline => widget.maxLines != 1;

  // Finds the closest scroll offset to the current scroll offset that fully
  // reveals the given caret rect. If the given rect's main axis extent is too
  // large to be fully revealed in `renderEditable`, it will be centered along
  // the main axis.
  //
  // If this is a multiline MongolEditableText (which means the Editable can only
  // scroll horizontally), the given rect's width will first be extended to match
  // `renderEditable.preferredLineWidth`, before the target scroll offset is
  // calculated.
  RevealedOffset _getOffsetToRevealCaret(Rect rect) {
    if (!_scrollController!.position.allowImplicitScrolling) {
      return RevealedOffset(offset: _scrollController!.offset, rect: rect);
    }

    final editableSize = renderEditable.size;
    final double additionalOffset;
    final Offset unitOffset;

    if (!_isMultiline) {
      additionalOffset = rect.height >= editableSize.height
          // Center `rect` if it's oversized.
          ? editableSize.height / 2 - rect.center.dy
          // Valid additional offsets range from (rect.bottom - size.height)
          // to (rect.top). Pick the closest one if out of range.
          : 0.0.clamp(rect.bottom - editableSize.height, rect.top);
      unitOffset = const Offset(0, 1);
    } else {
      // multiline
      // The caret is horizontally centered within the line. Expand the caret's
      // height so that it spans the line because we're going to ensure that the
      // entire expanded caret is scrolled into view.
      final expandedRect = Rect.fromCenter(
        center: rect.center,
        height: rect.height,
        width: math.max(rect.width, renderEditable.preferredLineWidth),
      );

      additionalOffset = expandedRect.width >= editableSize.width
          ? editableSize.width / 2 - expandedRect.center.dx
          : 0.0.clamp(
              expandedRect.right - editableSize.width, expandedRect.left);
      unitOffset = const Offset(1, 0);
    }

    // No overscrolling when encountering tall fonts/scripts that extend past
    // the ascent.
    final targetOffset = (additionalOffset + _scrollController!.offset).clamp(
      _scrollController!.position.minScrollExtent,
      _scrollController!.position.maxScrollExtent,
    );

    final offsetDelta = _scrollController!.offset - targetOffset;
    return RevealedOffset(
        rect: rect.shift(unitOffset * offsetDelta), offset: targetOffset);
  }

  bool get _hasInputConnection => _textInputConnection?.attached ?? false;

  bool get _needsAutofill => widget.autofillHints?.isNotEmpty ?? false;

  bool get _shouldBeInAutofillContext =>
      _needsAutofill && currentAutofillScope != null;

  void _openInputConnection() {
    if (!_shouldCreateInputConnection) {
      return;
    }
    if (!_hasInputConnection) {
      final localValue = _value;

      // When _needsAutofill == true && currentAutofillScope == null, autofill
      // is allowed but saving the user input from the text field is
      // discouraged.
      //
      // In case the autofillScope changes from a non-null value to null, or
      // _needsAutofill changes to false from true, the platform needs to be
      // notified to exclude this field from the autofill context. So we need to
      // provide the autofillId.
      // todo editor-fixes replace with below code
      // _textInputConnection = _needsAutofill && currentAutofillScope != null
      //     ? currentAutofillScope!.attach(this, textInputConfiguration)
      //     : TextInput.attach(
      //         this,
      //         _createTextInputConfiguration(
      //             _isInAutofillContext || _needsAutofill));
      _textInputConnection = _needsAutofill && currentAutofillScope != null
          ? currentAutofillScope!
              .attach(this, _effectiveAutofillClient.textInputConfiguration)
          : TextInput.attach(
              this, _effectiveAutofillClient.textInputConfiguration);
      _textInputConnection!.show();
      _updateSizeAndTransform();
      _updateComposingRectIfNeeded();
      _updateCaretRectIfNeeded();
      if (_needsAutofill) {
        // Request autofill AFTER the size and the transform have been sent to
        // the platform text input plugin.
        _textInputConnection!.requestAutofill();
      }

      final style = widget.style;
      _textInputConnection!
        ..setStyle(
          fontFamily: style.fontFamily,
          fontSize: style.fontSize,
          fontWeight: style.fontWeight,
          textDirection: TextDirection.ltr,
          textAlign: _rotatedTextAlign(widget.textAlign),
        )
        ..setEditingState(localValue);
    } else {
      _textInputConnection!.show();
    }
  }

  void _closeInputConnectionIfNeeded() {
    if (_hasInputConnection) {
      _textInputConnection!.close();
      _textInputConnection = null;
      _lastKnownRemoteTextEditingValue = null;
    }
  }

  void _openOrCloseInputConnectionIfNeeded() {
    if (_hasFocus && widget.focusNode.consumeKeyboardToken()) {
      _openInputConnection();
    } else if (!_hasFocus) {
      _closeInputConnectionIfNeeded();
      widget.controller.clearComposing();
    }
  }

  @override
  void connectionClosed() {
    if (_hasInputConnection) {
      _textInputConnection!.connectionClosedReceived();
      _textInputConnection = null;
      _lastKnownRemoteTextEditingValue = null;
      _finalizeEditing(TextInputAction.done, shouldUnfocus: true);
    }
  }

  /// Express interest in interacting with the keyboard.
  ///
  /// If this control is already attached to the keyboard, this function will
  /// request that the keyboard become visible. Otherwise, this function will
  /// ask the focus system that it become focused. If successful in acquiring
  /// focus, the control will then attach to the keyboard and request that the
  /// keyboard become visible.
  void requestKeyboard() {
    if (_hasFocus) {
      _openInputConnection();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void _updateOrDisposeSelectionOverlayIfNeeded() {
    if (_selectionOverlay != null) {
      if (_hasFocus) {
        _selectionOverlay!.update(_value);
      } else {
        _selectionOverlay!.dispose();
        _selectionOverlay = null;
      }
    }
  }

  @pragma('vm:notify-debugger-on-exception')
  void _handleSelectionChanged(
      TextSelection selection, SelectionChangedCause? cause) {
    // We return early if the selection is not valid. This can happen when the
    // text of [MongolEditableText] is updated at the same time as the selection is
    // changed by a gesture event.
    if (!widget.controller.isSelectionWithinTextBounds(selection)) return;

    widget.controller.selection = selection;

    // This will show the keyboard for all selection changes on the
    // editable widget, not just changes triggered by user gestures.
    requestKeyboard();
    if (widget.selectionControls == null) {
      _selectionOverlay?.dispose();
      _selectionOverlay = null;
    } else {
      if (_selectionOverlay == null) {
        _selectionOverlay = MongolTextSelectionOverlay(
          clipboardStatus: _clipboardStatus,
          context: context,
          value: _value,
          debugRequiredFor: widget,
          toolbarLayerLink: _toolbarLayerLink,
          startHandleLayerLink: _startHandleLayerLink,
          endHandleLayerLink: _endHandleLayerLink,
          renderObject: renderEditable,
          selectionControls: widget.selectionControls,
          selectionDelegate: this,
          dragStartBehavior: widget.dragStartBehavior,
          onSelectionHandleTapped: widget.onSelectionHandleTapped,
        );
      } else {
        _selectionOverlay!.update(_value);
      }
      _selectionOverlay!.handlesVisible = widget.showSelectionHandles;
      _selectionOverlay!.showHandles();
    }

    try {
      widget.onSelectionChanged?.call(selection, cause);
    } catch (exception, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'widgets',
        context:
            ErrorDescription('while calling onSelectionChanged for $cause'),
      ));
    }

    // To keep the cursor from blinking while it moves, restart the timer here.
    if (_cursorTimer != null) {
      _stopCursorTimer(resetCharTicks: false);
      _startCursorTimer();
    }
  }

  Rect? _currentCaretRect;

  void _handleCaretChanged(Rect caretRect) {
    _currentCaretRect = caretRect;
  }

  // Animation configuration for scrolling the caret back on screen.
  static const Duration _caretAnimationDuration = Duration(milliseconds: 100);
  static const Curve _caretAnimationCurve = Curves.fastOutSlowIn;

  bool _showCaretOnScreenScheduled = false;

  void _scheduleShowCaretOnScreen() {
    if (_showCaretOnScreenScheduled) {
      return;
    }
    _showCaretOnScreenScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((Duration _) {
      _showCaretOnScreenScheduled = false;
      if (_currentCaretRect == null || !_scrollController!.hasClients) {
        return;
      }

      final lineWidth = renderEditable.preferredLineWidth;

      // Enlarge the target rect by scrollPadding to ensure that caret is not
      // positioned directly at the edge after scrolling.
      var rightSpacing = widget.scrollPadding.right;
      if (_selectionOverlay?.selectionControls != null) {
        final handleWidth = _selectionOverlay!.selectionControls!
            .getHandleSize(lineWidth)
            .width;
        final interactiveHandleWidth = math.max(
          handleWidth,
          kMinInteractiveDimension,
        );
        final anchor = _selectionOverlay!.selectionControls!.getHandleAnchor(
          TextSelectionHandleType.collapsed,
          lineWidth,
        );
        final handleCenter = handleWidth / 2 - anchor.dx;
        rightSpacing = math.max(
          handleCenter + interactiveHandleWidth / 2,
          rightSpacing,
        );
      }

      final caretPadding = widget.scrollPadding.copyWith(right: rightSpacing);

      final targetOffset = _getOffsetToRevealCaret(_currentCaretRect!);

      _scrollController!.animateTo(
        targetOffset.offset,
        duration: _caretAnimationDuration,
        curve: _caretAnimationCurve,
      );

      renderEditable.showOnScreen(
        rect: caretPadding.inflateRect(targetOffset.rect),
        duration: _caretAnimationDuration,
        curve: _caretAnimationCurve,
      );
    });
  }

  // keeping "bottom" rather than changing it to "right" because it likely refers
  // to the keyboard location. But this might be wrong.
  late double _lastBottomViewInset;

  @override
  void didChangeMetrics() {
    if (_lastBottomViewInset !=
        WidgetsBinding.instance.window.viewInsets.bottom) {
      SchedulerBinding.instance.addPostFrameCallback((Duration _) {
        _selectionOverlay?.updateForScroll();
      });
      if (_lastBottomViewInset <
          WidgetsBinding.instance.window.viewInsets.bottom) {
        _scheduleShowCaretOnScreen();
      }
    }
    _lastBottomViewInset = WidgetsBinding.instance.window.viewInsets.bottom;
  }

  @pragma('vm:notify-debugger-on-exception')
  void _formatAndSetValue(TextEditingValue value, SelectionChangedCause? cause,
      {bool userInteraction = false}) {
    // Only apply input formatters if the text has changed (including uncommited
    // text in the composing region), or when the user committed the composing
    // text.
    // Gboard is very persistent in restoring the composing region. Applying
    // input formatters on composing-region-only changes (except clearing the
    // current composing region) is very infinite-loop-prone: the formatters
    // will keep trying to modify the composing region while Gboard will keep
    // trying to restore the original composing region.
    final textChanged = _value.text != value.text ||
        (!_value.composing.isCollapsed && value.composing.isCollapsed);
    final selectionChanged = _value.selection != value.selection;

    if (textChanged) {
      value = widget.inputFormatters?.fold<TextEditingValue>(
            value,
            (TextEditingValue newValue, TextInputFormatter formatter) =>
                formatter.formatEditUpdate(_value, newValue),
          ) ??
          value;
    }

    // Put all optional user callback invocations in a batch edit to prevent
    // sending multiple `TextInput.updateEditingValue` messages.
    beginBatchEdit();
    _value = value;
    // Changes made by the keyboard can sometimes be "out of band" for listening
    // components, so always send those events, even if we didn't think it
    // changed. Also, the user long pressing should always send a selection change
    // as well.
    if (selectionChanged ||
        (userInteraction &&
            (cause == SelectionChangedCause.longPress ||
                cause == SelectionChangedCause.keyboard))) {
      _handleSelectionChanged(_value.selection, cause);
    }
    if (textChanged) {
      try {
        widget.onChanged?.call(_value.text);
      } catch (exception, stack) {
        FlutterError.reportError(FlutterErrorDetails(
          exception: exception,
          stack: stack,
          library: 'widgets',
          context: ErrorDescription('while calling onChanged'),
        ));
      }
    }

    endBatchEdit();
  }

  void _onCursorColorTick() {
    renderEditable.cursorColor =
        widget.cursorColor.withOpacity(_cursorBlinkOpacityController.value);
    _cursorVisibilityNotifier.value =
        widget.showCursor && _cursorBlinkOpacityController.value > 0;
  }

  /// Whether the blinking cursor is actually visible at this precise moment
  /// (it's hidden half the time, since it blinks).
  @visibleForTesting
  bool get cursorCurrentlyVisible => _cursorBlinkOpacityController.value > 0;

  /// The cursor blink interval (the amount of time the cursor is in the "on"
  /// state or the "off" state). A complete cursor blink period is twice this
  /// value (half on, half off).
  @visibleForTesting
  Duration get cursorBlinkInterval => _kCursorBlinkHalfPeriod;

  /// The current status of the text selection handles.
  @visibleForTesting
  MongolTextSelectionOverlay? get selectionOverlay => _selectionOverlay;

  int _obscureShowCharTicksPending = 0;
  int? _obscureLatestCharIndex;

  void _cursorTick(Timer timer) {
    _targetCursorVisibility = !_targetCursorVisibility;
    final targetOpacity = _targetCursorVisibility ? 1.0 : 0.0;
    if (widget.cursorOpacityAnimates) {
      // If we want to show the cursor, we will animate the opacity to the value
      // of 1.0, and likewise if we want to make it disappear, to 0.0. An easing
      // curve is used for the animation to mimic the aesthetics of the native
      // iOS cursor.
      //
      // These values and curves have been obtained through eyeballing, so are
      // likely not exactly the same as the values for native iOS.
      _cursorBlinkOpacityController.animateTo(targetOpacity,
          curve: Curves.easeOut);
    } else {
      _cursorBlinkOpacityController.value = targetOpacity;
    }

    if (_obscureShowCharTicksPending > 0) {
      setState(() {
        _obscureShowCharTicksPending--;
      });
    }
  }

  void _cursorWaitForStart(Timer timer) {
    assert(_kCursorBlinkHalfPeriod > _fadeDuration);
    assert(!MongolEditableText.debugDeterministicCursor);
    _cursorTimer?.cancel();
    _cursorTimer = Timer.periodic(_kCursorBlinkHalfPeriod, _cursorTick);
  }

  void _startCursorTimer() {
    assert(_cursorTimer == null);
    _targetCursorVisibility = true;
    _cursorBlinkOpacityController.value = 1.0;
    if (MongolEditableText.debugDeterministicCursor) return;
    if (widget.cursorOpacityAnimates) {
      _cursorTimer =
          Timer.periodic(_kCursorBlinkWaitForStart, _cursorWaitForStart);
    } else {
      _cursorTimer = Timer.periodic(_kCursorBlinkHalfPeriod, _cursorTick);
    }
  }

  void _stopCursorTimer({bool resetCharTicks = true}) {
    _cursorTimer?.cancel();
    _cursorTimer = null;
    _targetCursorVisibility = false;
    _cursorBlinkOpacityController.value = 0.0;
    if (MongolEditableText.debugDeterministicCursor) return;
    if (resetCharTicks) _obscureShowCharTicksPending = 0;
    if (widget.cursorOpacityAnimates) {
      _cursorBlinkOpacityController.stop();
      _cursorBlinkOpacityController.value = 0.0;
    }
  }

  void _startOrStopCursorTimerIfNeeded() {
    if (_cursorTimer == null && _hasFocus && _value.selection.isCollapsed) {
      _startCursorTimer();
    } else if (_cursorTimer != null &&
        (!_hasFocus || !_value.selection.isCollapsed)) {
      _stopCursorTimer();
    }
  }

  void _didChangeTextEditingValue() {
    _updateRemoteEditingValueIfNeeded();
    _startOrStopCursorTimerIfNeeded();
    _updateOrDisposeSelectionOverlayIfNeeded();
    setState(() {
      /* We use widget.controller.value in build(). */
    });
    _adjacentLineAction.stopCurrentVerticalRunIfSelectionChanges();
  }

  void _handleFocusChanged() {
    _openOrCloseInputConnectionIfNeeded();
    _startOrStopCursorTimerIfNeeded();
    _updateOrDisposeSelectionOverlayIfNeeded();
    if (_hasFocus) {
      // Listen for changing viewInsets, which indicates keyboard showing up.
      WidgetsBinding.instance.addObserver(this);
      _lastBottomViewInset = WidgetsBinding.instance.window.viewInsets.bottom;
      if (!widget.readOnly) {
        _scheduleShowCaretOnScreen();
      }
      if (!_value.selection.isValid) {
        // Place cursor at the end if the selection is invalid when we receive focus.
        _handleSelectionChanged(
            TextSelection.collapsed(offset: _value.text.length), null);
      }
    } else {
      WidgetsBinding.instance.removeObserver(this);
      // Clear the selection and composition state if this widget lost focus.
      _value = TextEditingValue(text: _value.text);
    }
    updateKeepAlive();
  }

  void _updateSizeAndTransform() {
    if (_hasInputConnection) {
      final size = renderEditable.size;
      final transform = renderEditable.getTransformTo(null);
      _textInputConnection!.setEditableSizeAndTransform(size, transform);
      SchedulerBinding.instance
          .addPostFrameCallback((Duration _) => _updateSizeAndTransform());
    }
  }

  // Sends the current composing rect to the iOS text input plugin via the text
  // input channel. We need to keep sending the information even if no text is
  // currently marked, as the information usually lags behind. The text input
  // plugin needs to estimate the composing rect based on the latest caret rect,
  // when the composing rect info didn't arrive in time.
  void _updateComposingRectIfNeeded() {
    final composingRange = _value.composing;
    if (_hasInputConnection) {
      assert(mounted);
      var composingRect =
          renderEditable.getRectForComposingRange(composingRange);
      // Send the caret location instead if there's no marked text yet.
      if (composingRect == null) {
        assert(!composingRange.isValid || composingRange.isCollapsed);
        final offset = composingRange.isValid ? composingRange.start : 0;
        composingRect =
            renderEditable.getLocalRectForCaret(TextPosition(offset: offset));
      }
      _textInputConnection!.setComposingRect(composingRect);
      SchedulerBinding.instance
          .addPostFrameCallback((Duration _) => _updateComposingRectIfNeeded());
    }
  }

  void _updateCaretRectIfNeeded() {
    if (_hasInputConnection) {
      if (renderEditable.selection != null &&
          renderEditable.selection!.isValid &&
          renderEditable.selection!.isCollapsed) {
        final TextPosition currentTextPosition =
            TextPosition(offset: renderEditable.selection!.baseOffset);
        final Rect caretRect =
            renderEditable.getLocalRectForCaret(currentTextPosition);
        _textInputConnection!.setCaretRect(caretRect);
      }
      SchedulerBinding.instance
          .addPostFrameCallback((Duration _) => _updateCaretRectIfNeeded());
    }
  }

  /// The renderer for this widget's descendant.
  ///
  /// This property is typically used to notify the renderer of input gestures
  /// when [MongolRenderEditable.ignorePointer] is true.
  @override
  MongolRenderEditable get renderEditable =>
      _editableKey.currentContext!.findRenderObject()! as MongolRenderEditable;

  @override
  TextEditingValue get textEditingValue => _value;

  double get _devicePixelRatio => MediaQuery.of(context).devicePixelRatio;

  @override
  void userUpdateTextEditingValue(
      TextEditingValue value, SelectionChangedCause? cause) {
    // Compare the current TextEditingValue with the pre-format new
    // TextEditingValue value, in case the formatter would reject the change.
    final shouldShowCaret =
        widget.readOnly ? _value.selection != value.selection : _value != value;
    if (shouldShowCaret) {
      _scheduleShowCaretOnScreen();
    }
    _formatAndSetValue(value, cause, userInteraction: true);
  }

  @override
  void bringIntoView(TextPosition position) {
    final localRect = renderEditable.getLocalRectForCaret(position);
    final targetOffset = _getOffsetToRevealCaret(localRect);

    _scrollController!.jumpTo(targetOffset.offset);
    renderEditable.showOnScreen(rect: targetOffset.rect);
  }

  /// Shows the selection toolbar at the location of the current cursor.
  ///
  /// Returns `false` if a toolbar couldn't be shown, such as when the toolbar
  /// is already shown, or when no text selection currently exists.
  @override
  bool showToolbar() {
    // Web is using native dom elements to enable clipboard functionality of the
    // toolbar: copy, paste, select, cut. It might also provide additional
    // functionality depending on the browser (such as translate). Due to this
    // we should not show a Flutter toolbar for the editable text elements.
    if (kIsWeb) {
      return false;
    }

    if (_selectionOverlay == null || _selectionOverlay!.toolbarIsVisible) {
      return false;
    }

    _selectionOverlay!.showToolbar();
    return true;
  }

  @override
  void hideToolbar([bool hideHandles = true]) {
    if (hideHandles) {
      // Hide the handles and the toolbar.
      _selectionOverlay?.hide();
    } else {
      // Hide only the toolbar but not the handles.
      _selectionOverlay?.hideToolbar();
    }
  }

  /// Toggles the visibility of the toolbar.
  void toggleToolbar() {
    assert(_selectionOverlay != null);
    if (_selectionOverlay!.toolbarIsVisible) {
      hideToolbar();
    } else {
      showToolbar();
    }
  }

  @override
  String get autofillId => 'MongolEditableText-$hashCode';

  @override
  TextInputConfiguration get textInputConfiguration {
    final List<String>? autofillHints =
        widget.autofillHints?.toList(growable: false);
    final AutofillConfiguration autofillConfiguration = autofillHints != null
        ? AutofillConfiguration(
            uniqueIdentifier: autofillId,
            autofillHints: autofillHints,
            currentEditingValue: currentTextEditingValue,
          )
        : AutofillConfiguration.disabled;

    return TextInputConfiguration(
      inputType: widget.keyboardType,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      autocorrect: widget.autocorrect,
      enableSuggestions: widget.enableSuggestions,
      inputAction: widget.textInputAction ??
          (widget.keyboardType == TextInputType.multiline
              ? TextInputAction.newline
              : TextInputAction.done),
      keyboardAppearance: widget.keyboardAppearance,
      autofillConfiguration: autofillConfiguration,
    );
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    // unimplemented
  }

  VoidCallback? _semanticsOnCopy(TextSelectionControls? controls) {
    return widget.selectionEnabled &&
            copyEnabled &&
            _hasFocus &&
            controls?.canCopy(this) == true
        ? () => controls!.handleCopy(this, _clipboardStatus)
        : null;
  }

  VoidCallback? _semanticsOnCut(TextSelectionControls? controls) {
    return widget.selectionEnabled &&
            cutEnabled &&
            _hasFocus &&
            controls?.canCut(this) == true
        ? () => controls!.handleCut(this)
        : null;
  }

  VoidCallback? _semanticsOnPaste(TextSelectionControls? controls) {
    return widget.selectionEnabled &&
            pasteEnabled &&
            _hasFocus &&
            controls?.canPaste(this) == true &&
            (_clipboardStatus == null ||
                _clipboardStatus!.value == ClipboardStatus.pasteable)
        ? () => controls!.handlePaste(this)
        : null;
  }

  // --------------------------- Text Editing Actions ---------------------------

  _TextBoundary _characterBoundary(DirectionalTextEditingIntent intent) {
    final _TextBoundary atomicTextBoundary = widget.obscureText
        ? _CodeUnitBoundary(_value)
        : _CharacterBoundary(_value);
    return _CollapsedSelectionBoundary(atomicTextBoundary, intent.forward);
  }

  _TextBoundary _nextWordBoundary(DirectionalTextEditingIntent intent) {
    final _TextBoundary atomicTextBoundary;
    final _TextBoundary boundary;

    if (widget.obscureText) {
      atomicTextBoundary = _CodeUnitBoundary(_value);
      boundary = _DocumentBoundary(_value);
    } else {
      final TextEditingValue textEditingValue =
          _textEditingValueForTextLayoutMetrics;
      atomicTextBoundary = _CharacterBoundary(textEditingValue);
      // This isn't enough. Newline characters.
      boundary = _ExpandedTextBoundary(_WhitespaceBoundary(textEditingValue),
          _WordBoundary(renderEditable, textEditingValue));
    }

    final _MixedBoundary mixedBoundary = intent.forward
        ? _MixedBoundary(atomicTextBoundary, boundary)
        : _MixedBoundary(boundary, atomicTextBoundary);
    // Use a _MixedBoundary to make sure we don't leave invalid codepoints in
    // the field after deletion.
    return _CollapsedSelectionBoundary(mixedBoundary, intent.forward);
  }

  _TextBoundary _linebreak(DirectionalTextEditingIntent intent) {
    final _TextBoundary atomicTextBoundary;
    final _TextBoundary boundary;

    if (widget.obscureText) {
      atomicTextBoundary = _CodeUnitBoundary(_value);
      boundary = _DocumentBoundary(_value);
    } else {
      final TextEditingValue textEditingValue =
          _textEditingValueForTextLayoutMetrics;
      atomicTextBoundary = _CharacterBoundary(textEditingValue);
      boundary = _LineBreak(renderEditable, textEditingValue);
    }

    // The _MixedBoundary is to make sure we don't leave invalid code units in
    // the field after deletion.
    // `boundary` doesn't need to be wrapped in a _CollapsedSelectionBoundary,
    // since the document boundary is unique and the linebreak boundary is
    // already caret-location based.
    return intent.forward
        ? _MixedBoundary(
            _CollapsedSelectionBoundary(atomicTextBoundary, true), boundary)
        : _MixedBoundary(
            boundary, _CollapsedSelectionBoundary(atomicTextBoundary, false));
  }

  void _updateSelection(UpdateSelectionIntent intent) {
    bringIntoView(intent.newSelection.extent);
    userUpdateTextEditingValue(
      intent.currentTextEditingValue.copyWith(selection: intent.newSelection),
      intent.cause,
    );
  }

  late final Action<UpdateSelectionIntent> _updateSelectionAction =
      CallbackAction<UpdateSelectionIntent>(onInvoke: _updateSelection);

  late final _UpdateTextSelectionToAdjacentLineAction<
          ExtendSelectionVerticallyToAdjacentLineIntent> _adjacentLineAction =
      _UpdateTextSelectionToAdjacentLineAction<
          ExtendSelectionVerticallyToAdjacentLineIntent>(this);

  _TextBoundary _documentBoundary(DirectionalTextEditingIntent intent) =>
      _DocumentBoundary(_value);

  Action<T> _makeOverridable<T extends Intent>(Action<T> defaultAction) {
    return Action<T>.overridable(
        context: context, defaultAction: defaultAction);
  }

  void _replaceText(ReplaceTextIntent intent) {
    final TextEditingValue oldValue = _value;
    final TextEditingValue newValue = intent.currentTextEditingValue.replaced(
      intent.replacementRange,
      intent.replacementText,
    );
    userUpdateTextEditingValue(newValue, intent.cause);

    // If there's no change in text and selection (e.g. when selecting and
    // pasting identical text), the widget won't be rebuilt on value update.
    // Handle this by calling _didChangeTextEditingValue() so caret and scroll
    // updates can happen.
    if (newValue == oldValue) {
      _didChangeTextEditingValue();
    }
  }

  late final Action<ReplaceTextIntent> _replaceTextAction =
      CallbackAction<ReplaceTextIntent>(onInvoke: _replaceText);

  // Scrolls either to the beginning or end of the document depending on the
  // intent's `forward` parameter.
  void _scrollToDocumentBoundary(ScrollToDocumentBoundaryIntent intent) {
    if (intent.forward) {
      bringIntoView(TextPosition(offset: _value.text.length));
    } else {
      bringIntoView(const TextPosition(offset: 0));
    }
  }

  void _expandSelectionToDocumentBoundary(
      ExpandSelectionToDocumentBoundaryIntent intent) {
    final _TextBoundary textBoundary = _documentBoundary(intent);
    _expandSelection(intent.forward, textBoundary, true);
  }

  void _expandSelectionToLinebreak(ExpandSelectionToLineBreakIntent intent) {
    final _TextBoundary textBoundary = _linebreak(intent);
    _expandSelection(intent.forward, textBoundary);
  }

  void _expandSelection(bool forward, _TextBoundary textBoundary,
      [bool extentAtIndex = false]) {
    final TextSelection textBoundarySelection =
        textBoundary.textEditingValue.selection;
    if (!textBoundarySelection.isValid) {
      return;
    }

    final bool inOrder =
        textBoundarySelection.baseOffset <= textBoundarySelection.extentOffset;
    final bool towardsExtent = forward == inOrder;
    final TextPosition position = towardsExtent
        ? textBoundarySelection.extent
        : textBoundarySelection.base;

    final TextPosition newExtent = forward
        ? textBoundary.getTrailingTextBoundaryAt(position)
        : textBoundary.getLeadingTextBoundaryAt(position);

    final TextSelection newSelection = textBoundarySelection.expandTo(
        newExtent, textBoundarySelection.isCollapsed || extentAtIndex);
    userUpdateTextEditingValue(
      _value.copyWith(selection: newSelection),
      SelectionChangedCause.keyboard,
    );
    bringIntoView(newSelection.extent);
  }

  Object? _hideToolbarIfVisible(DismissIntent intent) {
    if (_selectionOverlay?.toolbarIsVisible ?? false) {
      hideToolbar(false);
      return null;
    }
    return Actions.invoke(context, intent);
  }

  late final Map<Type, Action<Intent>> _actions = <Type, Action<Intent>>{
    DoNothingAndStopPropagationTextIntent: DoNothingAction(consumesKey: false),
    ReplaceTextIntent: _replaceTextAction,
    UpdateSelectionIntent: _updateSelectionAction,
    DirectionalFocusIntent: DirectionalFocusAction.forTextField(),
    DismissIntent:
        CallbackAction<DismissIntent>(onInvoke: _hideToolbarIfVisible),

    // Delete
    DeleteCharacterIntent: _makeOverridable(
        _DeleteTextAction<DeleteCharacterIntent>(this, _characterBoundary)),
    DeleteToNextWordBoundaryIntent: _makeOverridable(
        _DeleteTextAction<DeleteToNextWordBoundaryIntent>(
            this, _nextWordBoundary)),
    DeleteToLineBreakIntent: _makeOverridable(
        _DeleteTextAction<DeleteToLineBreakIntent>(this, _linebreak)),

    // Extend/Move Selection
    ExtendSelectionByCharacterIntent: _makeOverridable(
        _UpdateTextSelectionAction<ExtendSelectionByCharacterIntent>(
      this,
      false,
      _characterBoundary,
    )),
    ExtendSelectionToNextWordBoundaryIntent: _makeOverridable(
        _UpdateTextSelectionAction<ExtendSelectionToNextWordBoundaryIntent>(
            this, true, _nextWordBoundary)),
    ExtendSelectionToLineBreakIntent: _makeOverridable(
        _UpdateTextSelectionAction<ExtendSelectionToLineBreakIntent>(
            this, true, _linebreak)),
    ExpandSelectionToLineBreakIntent: _makeOverridable(
        CallbackAction<ExpandSelectionToLineBreakIntent>(
            onInvoke: _expandSelectionToLinebreak)),
    ExpandSelectionToDocumentBoundaryIntent: _makeOverridable(
        CallbackAction<ExpandSelectionToDocumentBoundaryIntent>(
            onInvoke: _expandSelectionToDocumentBoundary)),
    ExtendSelectionVerticallyToAdjacentLineIntent:
        _makeOverridable(_adjacentLineAction),
    ExtendSelectionToDocumentBoundaryIntent: _makeOverridable(
        _UpdateTextSelectionAction<ExtendSelectionToDocumentBoundaryIntent>(
            this, true, _documentBoundary)),
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent: _makeOverridable(
        _ExtendSelectionOrCaretPositionAction(this, _nextWordBoundary)),
    ScrollToDocumentBoundaryIntent: _makeOverridable(
        CallbackAction<ScrollToDocumentBoundaryIntent>(
            onInvoke: _scrollToDocumentBoundary)),

    // Copy Paste
    SelectAllTextIntent: _makeOverridable(_SelectAllAction(this)),
    CopySelectionTextIntent: _makeOverridable(_CopySelectionAction(this)),
    PasteTextIntent: _makeOverridable(CallbackAction<PasteTextIntent>(
        onInvoke: (PasteTextIntent intent) => pasteText(intent.cause))),
  };

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasMediaQuery(context));
    _focusAttachment!.reparent();
    super.build(context); // See AutomaticKeepAliveClientMixin.

    final controls = widget.selectionControls;
    return MouseRegion(
      cursor: widget.mouseCursor ?? SystemMouseCursors.text,
      child: DefaultMongolTextEditingShortcuts(
        child: Actions(
          actions: _actions,
          child: Focus(
            focusNode: widget.focusNode,
            includeSemantics: false,
            debugLabel: 'MongolEditableText',
            child: Scrollable(
              excludeFromSemantics: true,
              axisDirection:
                  _isMultiline ? AxisDirection.right : AxisDirection.down,
              controller: _scrollController,
              physics: widget.scrollPhysics,
              dragStartBehavior: widget.dragStartBehavior,
              restorationId: widget.restorationId,
              scrollBehavior: widget.scrollBehavior ??
                  // Remove scrollbars if only single line
                  (_isMultiline
                      ? null
                      : ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false)),
              viewportBuilder: (BuildContext context, ViewportOffset offset) {
                return CompositedTransformTarget(
                  link: _toolbarLayerLink,
                  child: Semantics(
                    onCopy: _semanticsOnCopy(controls),
                    onCut: _semanticsOnCut(controls),
                    onPaste: _semanticsOnPaste(controls),
                    textDirection: TextDirection.ltr,
                    child: _MongolEditable(
                      key: _editableKey,
                      startHandleLayerLink: _startHandleLayerLink,
                      endHandleLayerLink: _endHandleLayerLink,
                      textSpan: buildTextSpan(),
                      value: _value,
                      cursorColor: _cursorColor,
                      showCursor: MongolEditableText.debugDeterministicCursor
                          ? ValueNotifier<bool>(widget.showCursor)
                          : _cursorVisibilityNotifier,
                      forceLine: widget.forceLine,
                      readOnly: widget.readOnly,
                      hasFocus: _hasFocus,
                      maxLines: widget.maxLines,
                      minLines: widget.minLines,
                      expands: widget.expands,
                      selectionColor: widget.selectionColor,
                      textScaleFactor: widget.textScaleFactor ??
                          MediaQuery.textScaleFactorOf(context),
                      textAlign: widget.textAlign,
                      obscuringCharacter: widget.obscuringCharacter,
                      obscureText: widget.obscureText,
                      autocorrect: widget.autocorrect,
                      enableSuggestions: widget.enableSuggestions,
                      offset: offset,
                      onCaretChanged: _handleCaretChanged,
                      rendererIgnoresPointer: widget.rendererIgnoresPointer,
                      cursorWidth: widget.cursorWidth,
                      cursorHeight: widget.cursorHeight,
                      cursorRadius: widget.cursorRadius,
                      cursorOffset: widget.cursorOffset ?? Offset.zero,
                      enableInteractiveSelection:
                          widget.enableInteractiveSelection,
                      textSelectionDelegate: this,
                      devicePixelRatio: _devicePixelRatio,
                      clipBehavior: widget.clipBehavior,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Builds [TextSpan] from current editing value.
  ///
  /// By default makes text in composing range appear as underlined.
  /// Descendants can override this method to customize appearance of text.
  TextSpan buildTextSpan() {
    if (widget.obscureText) {
      var text = _value.text;
      text = widget.obscuringCharacter * text.length;
      // Reveal the latest character in an obscured field only on mobile.
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.fuchsia) {
        final o =
            _obscureShowCharTicksPending > 0 ? _obscureLatestCharIndex : null;
        if (o != null && o >= 0 && o < text.length) {
          text = text.replaceRange(o, o + 1, _value.text.substring(o, o + 1));
        }
      }
      return TextSpan(style: widget.style, text: text);
    }
    // Read only mode should not paint text composing.
    return widget.controller.buildTextSpan(
      context: context,
      style: widget.style,
      withComposing: !widget.readOnly,
    );
  }
}

class _MongolEditable extends LeafRenderObjectWidget {
  const _MongolEditable({
    Key? key,
    required this.textSpan,
    required this.value,
    required this.startHandleLayerLink,
    required this.endHandleLayerLink,
    this.cursorColor,
    required this.showCursor,
    required this.forceLine,
    required this.readOnly,
    required this.hasFocus,
    required this.maxLines,
    this.minLines,
    required this.expands,
    this.selectionColor,
    required this.textScaleFactor,
    required this.textAlign,
    required this.obscuringCharacter,
    required this.obscureText,
    required this.autocorrect,
    required this.enableSuggestions,
    required this.offset,
    this.onCaretChanged,
    this.rendererIgnoresPointer = false,
    this.cursorWidth,
    required this.cursorHeight,
    this.cursorRadius,
    required this.cursorOffset,
    this.enableInteractiveSelection = true,
    required this.textSelectionDelegate,
    required this.devicePixelRatio,
    required this.clipBehavior,
  }) : super(key: key);

  final TextSpan textSpan;
  final TextEditingValue value;
  final Color? cursorColor;
  final LayerLink startHandleLayerLink;
  final LayerLink endHandleLayerLink;
  final ValueNotifier<bool> showCursor;
  final bool forceLine;
  final bool readOnly;
  final bool hasFocus;
  final int? maxLines;
  final int? minLines;
  final bool expands;
  final Color? selectionColor;
  final double textScaleFactor;
  final MongolTextAlign textAlign;
  final String obscuringCharacter;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final ViewportOffset offset;
  final CaretChangedHandler? onCaretChanged;
  final bool rendererIgnoresPointer;
  final double? cursorWidth;
  final double cursorHeight;
  final Radius? cursorRadius;
  final Offset cursorOffset;
  final bool enableInteractiveSelection;
  final TextSelectionDelegate textSelectionDelegate;
  final double devicePixelRatio;
  final Clip clipBehavior;

  @override
  MongolRenderEditable createRenderObject(BuildContext context) {
    return MongolRenderEditable(
      text: textSpan,
      cursorColor: cursorColor,
      startHandleLayerLink: startHandleLayerLink,
      endHandleLayerLink: endHandleLayerLink,
      showCursor: showCursor,
      forceLine: forceLine,
      readOnly: readOnly,
      hasFocus: hasFocus,
      maxLines: maxLines,
      minLines: minLines,
      expands: expands,
      selectionColor: selectionColor,
      textScaleFactor: textScaleFactor,
      textAlign: textAlign,
      selection: value.selection,
      offset: offset,
      onCaretChanged: onCaretChanged,
      ignorePointer: rendererIgnoresPointer,
      obscuringCharacter: obscuringCharacter,
      obscureText: obscureText,
      cursorWidth: cursorWidth,
      cursorHeight: cursorHeight,
      cursorRadius: cursorRadius,
      cursorOffset: cursorOffset,
      enableInteractiveSelection: enableInteractiveSelection,
      textSelectionDelegate: textSelectionDelegate,
      devicePixelRatio: devicePixelRatio,
      clipBehavior: clipBehavior,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, MongolRenderEditable renderObject) {
    renderObject
      ..text = textSpan
      ..cursorColor = cursorColor
      ..startHandleLayerLink = startHandleLayerLink
      ..endHandleLayerLink = endHandleLayerLink
      ..showCursor = showCursor
      ..forceLine = forceLine
      ..readOnly = readOnly
      ..hasFocus = hasFocus
      ..maxLines = maxLines
      ..minLines = minLines
      ..expands = expands
      ..selectionColor = selectionColor
      ..textScaleFactor = textScaleFactor
      ..textAlign = textAlign
      ..selection = value.selection
      ..offset = offset
      ..onCaretChanged = onCaretChanged
      ..ignorePointer = rendererIgnoresPointer
      ..obscuringCharacter = obscuringCharacter
      ..obscureText = obscureText
      ..cursorWidth = cursorWidth
      ..cursorHeight = cursorHeight
      ..cursorRadius = cursorRadius
      ..cursorOffset = cursorOffset
      ..textSelectionDelegate = textSelectionDelegate
      ..devicePixelRatio = devicePixelRatio
      ..clipBehavior = clipBehavior;
  }
}

/// An interface for retrieving the logical text boundary (left-closed-right-open)
/// at a given location in a document.
///
/// Depending on the implementation of the [_TextBoundary], the input
/// [TextPosition] can either point to a code unit, or a position between 2 code
/// units (which can be visually represented by the caret if the selection were
/// to collapse to that position).
///
/// For example, [_LineBreak] interprets the input [TextPosition] as a caret
/// location, since in Flutter the caret is generally painted between the
/// character the [TextPosition] points to and its previous character, and
/// [_LineBreak] cares about the affinity of the input [TextPosition]. Most
/// other text boundaries however, interpret the input [TextPosition] as the
/// location of a code unit in the document, since it's easier to reason about
/// the text boundary given a code unit in the text.
///
/// To convert a "code-unit-based" [_TextBoundary] to "caret-location-based",
/// use the [_CollapsedSelectionBoundary] combinator.
abstract class _TextBoundary {
  const _TextBoundary();

  TextEditingValue get textEditingValue;

  /// Returns the leading text boundary at the given location, inclusive.
  TextPosition getLeadingTextBoundaryAt(TextPosition position);

  /// Returns the trailing text boundary at the given location, exclusive.
  TextPosition getTrailingTextBoundaryAt(TextPosition position);

  TextRange getTextBoundaryAt(TextPosition position) {
    return TextRange(
      start: getLeadingTextBoundaryAt(position).offset,
      end: getTrailingTextBoundaryAt(position).offset,
    );
  }
}

// -----------------------------  Text Boundaries -----------------------------

class _CodeUnitBoundary extends _TextBoundary {
  const _CodeUnitBoundary(this.textEditingValue);

  @override
  final TextEditingValue textEditingValue;

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) =>
      TextPosition(offset: position.offset);
  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) => TextPosition(
      offset: math.min(position.offset + 1, textEditingValue.text.length));
}

// The word modifier generally removes the word boundaries around white spaces
// (and newlines), IOW white spaces and some other punctuations are considered
// a part of the next word in the search direction.
class _WhitespaceBoundary extends _TextBoundary {
  const _WhitespaceBoundary(this.textEditingValue);

  @override
  final TextEditingValue textEditingValue;

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) {
    for (int index = position.offset; index >= 0; index -= 1) {
      if (!TextLayoutMetrics.isWhitespace(
          textEditingValue.text.codeUnitAt(index))) {
        return TextPosition(offset: index);
      }
    }
    return const TextPosition(offset: 0);
  }

  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) {
    for (int index = position.offset;
        index < textEditingValue.text.length;
        index += 1) {
      if (!TextLayoutMetrics.isWhitespace(
          textEditingValue.text.codeUnitAt(index))) {
        return TextPosition(offset: index + 1);
      }
    }
    return TextPosition(offset: textEditingValue.text.length);
  }
}

// Most apps delete the entire grapheme when the backspace key is pressed.
// Also always put the new caret location to character boundaries to avoid
// sending malformed UTF-16 code units to the paragraph builder.
class _CharacterBoundary extends _TextBoundary {
  const _CharacterBoundary(this.textEditingValue);

  @override
  final TextEditingValue textEditingValue;

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) {
    final int endOffset =
        math.min(position.offset + 1, textEditingValue.text.length);
    return TextPosition(
      offset:
          CharacterRange.at(textEditingValue.text, position.offset, endOffset)
              .stringBeforeLength,
    );
  }

  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) {
    final int endOffset =
        math.min(position.offset + 1, textEditingValue.text.length);
    final CharacterRange range =
        CharacterRange.at(textEditingValue.text, position.offset, endOffset);
    return TextPosition(
      offset: textEditingValue.text.length - range.stringAfterLength,
    );
  }

  @override
  TextRange getTextBoundaryAt(TextPosition position) {
    final int endOffset =
        math.min(position.offset + 1, textEditingValue.text.length);
    final CharacterRange range =
        CharacterRange.at(textEditingValue.text, position.offset, endOffset);
    return TextRange(
      start: range.stringBeforeLength,
      end: textEditingValue.text.length - range.stringAfterLength,
    );
  }
}

// [UAX #29](https://unicode.org/reports/tr29/) defined word boundaries.
class _WordBoundary extends _TextBoundary {
  const _WordBoundary(this.textLayout, this.textEditingValue);

  final TextLayoutMetrics textLayout;

  @override
  final TextEditingValue textEditingValue;

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) {
    return TextPosition(
      offset: textLayout.getWordBoundary(position).start,
      // Word boundary seems to always report downstream on many platforms.
      affinity:
          TextAffinity.downstream, // ignore: avoid_redundant_argument_values
    );
  }

  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) {
    return TextPosition(
      offset: textLayout.getWordBoundary(position).end,
      // Word boundary seems to always report downstream on many platforms.
      affinity:
          TextAffinity.downstream, // ignore: avoid_redundant_argument_values
    );
  }
}

// The linebreaks of the current text layout. The input [TextPosition]s are
// interpreted as caret locations because [TextPainter.getLineAtOffset] is
// text-affinity-aware.
class _LineBreak extends _TextBoundary {
  const _LineBreak(
    this.textLayout,
    this.textEditingValue,
  );

  final TextLayoutMetrics textLayout;

  @override
  final TextEditingValue textEditingValue;

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) {
    return TextPosition(
      offset: textLayout.getLineAtOffset(position).start,
    );
  }

  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) {
    return TextPosition(
      offset: textLayout.getLineAtOffset(position).end,
      affinity: TextAffinity.upstream,
    );
  }
}

// The document boundary is unique and is a constant function of the input
// position.
class _DocumentBoundary extends _TextBoundary {
  const _DocumentBoundary(this.textEditingValue);

  @override
  final TextEditingValue textEditingValue;

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) =>
      const TextPosition(offset: 0);
  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) {
    return TextPosition(
      offset: textEditingValue.text.length,
      affinity: TextAffinity.upstream,
    );
  }
}

// ------------------------  Text Boundary Combinators ------------------------

// Expands the innerTextBoundary with outerTextBoundary.
class _ExpandedTextBoundary extends _TextBoundary {
  _ExpandedTextBoundary(this.innerTextBoundary, this.outerTextBoundary);

  final _TextBoundary innerTextBoundary;
  final _TextBoundary outerTextBoundary;

  @override
  TextEditingValue get textEditingValue {
    assert(innerTextBoundary.textEditingValue ==
        outerTextBoundary.textEditingValue);
    return innerTextBoundary.textEditingValue;
  }

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) {
    return outerTextBoundary.getLeadingTextBoundaryAt(
      innerTextBoundary.getLeadingTextBoundaryAt(position),
    );
  }

  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) {
    return outerTextBoundary.getTrailingTextBoundaryAt(
      innerTextBoundary.getTrailingTextBoundaryAt(position),
    );
  }
}

// Force the innerTextBoundary to interpret the input [TextPosition]s as caret
// locations instead of code unit positions.
//
// The innerTextBoundary must be a [_TextBoundary] that interprets the input
// [TextPosition]s as code unit positions.
class _CollapsedSelectionBoundary extends _TextBoundary {
  _CollapsedSelectionBoundary(this.innerTextBoundary, this.isForward);

  final _TextBoundary innerTextBoundary;
  final bool isForward;

  @override
  TextEditingValue get textEditingValue => innerTextBoundary.textEditingValue;

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) {
    return isForward
        ? innerTextBoundary.getLeadingTextBoundaryAt(position)
        : position.offset <= 0
            ? const TextPosition(offset: 0)
            : innerTextBoundary.getLeadingTextBoundaryAt(
                TextPosition(offset: position.offset - 1));
  }

  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) {
    return isForward
        ? innerTextBoundary.getTrailingTextBoundaryAt(position)
        : position.offset <= 0
            ? const TextPosition(offset: 0)
            : innerTextBoundary.getTrailingTextBoundaryAt(
                TextPosition(offset: position.offset - 1));
  }
}

// A _TextBoundary that creates a [TextRange] where its start is from the
// specified leading text boundary and its end is from the specified trailing
// text boundary.
class _MixedBoundary extends _TextBoundary {
  _MixedBoundary(this.leadingTextBoundary, this.trailingTextBoundary);

  final _TextBoundary leadingTextBoundary;
  final _TextBoundary trailingTextBoundary;

  @override
  TextEditingValue get textEditingValue {
    assert(leadingTextBoundary.textEditingValue ==
        trailingTextBoundary.textEditingValue);
    return leadingTextBoundary.textEditingValue;
  }

  @override
  TextPosition getLeadingTextBoundaryAt(TextPosition position) =>
      leadingTextBoundary.getLeadingTextBoundaryAt(position);

  @override
  TextPosition getTrailingTextBoundaryAt(TextPosition position) =>
      trailingTextBoundary.getTrailingTextBoundaryAt(position);
}

// -------------------------------  Text Actions -------------------------------
class _DeleteTextAction<T extends DirectionalTextEditingIntent>
    extends ContextAction<T> {
  _DeleteTextAction(this.state, this.getTextBoundariesForIntent);

  final MongolEditableTextState state;
  final _TextBoundary Function(T intent) getTextBoundariesForIntent;

  TextRange _expandNonCollapsedRange(TextEditingValue value) {
    final TextRange selection = value.selection;
    assert(selection.isValid);
    assert(!selection.isCollapsed);
    final _TextBoundary atomicBoundary = state.widget.obscureText
        ? _CodeUnitBoundary(value)
        : _CharacterBoundary(value);

    return TextRange(
      start: atomicBoundary
          .getLeadingTextBoundaryAt(TextPosition(offset: selection.start))
          .offset,
      end: atomicBoundary
          .getTrailingTextBoundaryAt(TextPosition(offset: selection.end - 1))
          .offset,
    );
  }

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    if (kDebugMode) {
      print('mongol_editable_text -> _DeleteTextAction.invoke');
    }
    final TextSelection selection = state._value.selection;
    assert(selection.isValid);

    if (!selection.isCollapsed) {
      return Actions.invoke(
        context!,
        ReplaceTextIntent(
            state._value,
            '',
            _expandNonCollapsedRange(state._value),
            SelectionChangedCause.keyboard),
      );
    }

    final _TextBoundary textBoundary = getTextBoundariesForIntent(intent);
    if (!textBoundary.textEditingValue.selection.isValid) {
      return null;
    }
    if (!textBoundary.textEditingValue.selection.isCollapsed) {
      return Actions.invoke(
        context!,
        ReplaceTextIntent(
            state._value,
            '',
            _expandNonCollapsedRange(textBoundary.textEditingValue),
            SelectionChangedCause.keyboard),
      );
    }

    return Actions.invoke(
      context!,
      ReplaceTextIntent(
        textBoundary.textEditingValue,
        '',
        textBoundary
            .getTextBoundaryAt(textBoundary.textEditingValue.selection.base),
        SelectionChangedCause.keyboard,
      ),
    );
  }

  @override
  bool get isActionEnabled =>
      !state.widget.readOnly && state._value.selection.isValid;
}

class _UpdateTextSelectionAction<T extends DirectionalCaretMovementIntent>
    extends ContextAction<T> {
  _UpdateTextSelectionAction(
    this.state,
    this.ignoreNonCollapsedSelection,
    this.getTextBoundariesForIntent,
  );

  final MongolEditableTextState state;
  final bool ignoreNonCollapsedSelection;
  final _TextBoundary Function(T intent) getTextBoundariesForIntent;

  static const int newlineCodeUnit = 10;

  // Returns true iff the given position is at a wordwrap boundary in the
  // upstream position.
  bool _isAtWordwrapUpstream(TextPosition position) {
    final TextPosition end = TextPosition(
      offset: state.renderEditable.getLineAtOffset(position).end,
      affinity: TextAffinity.upstream,
    );
    return end == position &&
        end.offset != state.textEditingValue.text.length &&
        state.textEditingValue.text.codeUnitAt(position.offset) !=
            newlineCodeUnit;
  }

  // Returns true iff the given position at a wordwrap boundary in the
  // downstream position.
  bool _isAtWordwrapDownstream(TextPosition position) {
    final TextPosition start = TextPosition(
      offset: state.renderEditable.getLineAtOffset(position).start,
    );
    return start == position &&
        start.offset != 0 &&
        state.textEditingValue.text.codeUnitAt(position.offset - 1) !=
            newlineCodeUnit;
  }

  @override
  Object? invoke(T intent, [BuildContext? context]) {
    final TextSelection selection = state._value.selection;
    assert(selection.isValid);

    final bool collapseSelection =
        intent.collapseSelection || !state.widget.selectionEnabled;
    // Collapse to the logical start/end.
    TextSelection collapse(TextSelection selection) {
      assert(selection.isValid);
      assert(!selection.isCollapsed);
      return selection.copyWith(
        baseOffset: intent.forward ? selection.end : selection.start,
        extentOffset: intent.forward ? selection.end : selection.start,
      );
    }

    if (!selection.isCollapsed &&
        !ignoreNonCollapsedSelection &&
        collapseSelection) {
      return Actions.invoke(
        context!,
        UpdateSelectionIntent(
            state._value, collapse(selection), SelectionChangedCause.keyboard),
      );
    }

    final _TextBoundary textBoundary = getTextBoundariesForIntent(intent);
    final TextSelection textBoundarySelection =
        textBoundary.textEditingValue.selection;
    if (!textBoundarySelection.isValid) {
      return null;
    }
    if (!textBoundarySelection.isCollapsed &&
        !ignoreNonCollapsedSelection &&
        collapseSelection) {
      return Actions.invoke(
        context!,
        UpdateSelectionIntent(state._value, collapse(textBoundarySelection),
            SelectionChangedCause.keyboard),
      );
    }

    TextPosition extent = textBoundarySelection.extent;

    // If continuesAtWrap is true extent and is at the relevant wordwrap, then
    // move it just to the other side of the wordwrap.
    if (intent.continuesAtWrap) {
      if (intent.forward && _isAtWordwrapUpstream(extent)) {
        extent = TextPosition(
          offset: extent.offset,
        );
      } else if (!intent.forward && _isAtWordwrapDownstream(extent)) {
        extent = TextPosition(
          offset: extent.offset,
          affinity: TextAffinity.upstream,
        );
      }
    }

    final TextPosition newExtent = intent.forward
        ? textBoundary.getTrailingTextBoundaryAt(extent)
        : textBoundary.getLeadingTextBoundaryAt(extent);

    final TextSelection newSelection = collapseSelection
        ? TextSelection.fromPosition(newExtent)
        : textBoundarySelection.extendTo(newExtent);

    // If collapseAtReversal is true and would have an effect, collapse it.
    if (!selection.isCollapsed &&
        intent.collapseAtReversal &&
        (selection.baseOffset < selection.extentOffset !=
            newSelection.baseOffset < newSelection.extentOffset)) {
      return Actions.invoke(
        context!,
        UpdateSelectionIntent(
          state._value,
          TextSelection.fromPosition(selection.base),
          SelectionChangedCause.keyboard,
        ),
      );
    }

    return Actions.invoke(
      context!,
      UpdateSelectionIntent(textBoundary.textEditingValue, newSelection,
          SelectionChangedCause.keyboard),
    );
  }

  @override
  bool get isActionEnabled => state._value.selection.isValid;
}

class _ExtendSelectionOrCaretPositionAction extends ContextAction<
    ExtendSelectionToNextWordBoundaryOrCaretLocationIntent> {
  _ExtendSelectionOrCaretPositionAction(
      this.state, this.getTextBoundariesForIntent);

  final MongolEditableTextState state;
  final _TextBoundary Function(
          ExtendSelectionToNextWordBoundaryOrCaretLocationIntent intent)
      getTextBoundariesForIntent;

  @override
  Object? invoke(ExtendSelectionToNextWordBoundaryOrCaretLocationIntent intent,
      [BuildContext? context]) {
    final TextSelection selection = state._value.selection;
    assert(selection.isValid);

    final _TextBoundary textBoundary = getTextBoundariesForIntent(intent);
    final TextSelection textBoundarySelection =
        textBoundary.textEditingValue.selection;
    if (!textBoundarySelection.isValid) {
      return null;
    }

    final TextPosition extent = textBoundarySelection.extent;
    final TextPosition newExtent = intent.forward
        ? textBoundary.getTrailingTextBoundaryAt(extent)
        : textBoundary.getLeadingTextBoundaryAt(extent);

    final TextSelection newSelection =
        (newExtent.offset - textBoundarySelection.baseOffset) *
                    (textBoundarySelection.extentOffset -
                        textBoundarySelection.baseOffset) <
                0
            ? textBoundarySelection.copyWith(
                extentOffset: textBoundarySelection.baseOffset,
                affinity: textBoundarySelection.extentOffset >
                        textBoundarySelection.baseOffset
                    ? TextAffinity.downstream
                    : TextAffinity.upstream,
              )
            : textBoundarySelection.extendTo(newExtent);

    return Actions.invoke(
      context!,
      UpdateSelectionIntent(textBoundary.textEditingValue, newSelection,
          SelectionChangedCause.keyboard),
    );
  }

  @override
  bool get isActionEnabled =>
      state.widget.selectionEnabled && state._value.selection.isValid;
}

class _UpdateTextSelectionToAdjacentLineAction<
    T extends DirectionalCaretMovementIntent> extends ContextAction<T> {
  _UpdateTextSelectionToAdjacentLineAction(this.state);

  final MongolEditableTextState state;

  HorizontalCaretMovementRun? _horizontalMovementRun;
  TextSelection? _runSelection;

  void stopCurrentVerticalRunIfSelectionChanges() {
    final TextSelection? runSelection = _runSelection;
    if (runSelection == null) {
      assert(_horizontalMovementRun == null);
      return;
    }
    _runSelection = state._value.selection;
    final TextSelection currentSelection = state.widget.controller.selection;
    final bool continueCurrentRun = currentSelection.isValid &&
        currentSelection.isCollapsed &&
        currentSelection.baseOffset == runSelection.baseOffset &&
        currentSelection.extentOffset == runSelection.extentOffset;
    if (!continueCurrentRun) {
      _horizontalMovementRun = null;
      _runSelection = null;
    }
  }

  @override
  void invoke(T intent, [BuildContext? context]) {
    assert(state._value.selection.isValid);

    final bool collapseSelection =
        intent.collapseSelection || !state.widget.selectionEnabled;
    final TextEditingValue value = state._textEditingValueForTextLayoutMetrics;
    if (!value.selection.isValid) {
      return;
    }

    if (_horizontalMovementRun?.isValid == false) {
      _horizontalMovementRun = null;
      _runSelection = null;
    }

    final HorizontalCaretMovementRun currentRun = _horizontalMovementRun ??
        state.renderEditable.startHorizontalCaretMovement(
            state.renderEditable.selection!.extent);

    final bool shouldMove =
        intent.forward ? currentRun.moveNext() : currentRun.movePrevious();
    final TextPosition newExtent = shouldMove
        ? currentRun.current
        : (intent.forward
            ? TextPosition(offset: state._value.text.length)
            : const TextPosition(offset: 0));
    final TextSelection newSelection = collapseSelection
        ? TextSelection.fromPosition(newExtent)
        : value.selection.extendTo(newExtent);

    Actions.invoke(
      context!,
      UpdateSelectionIntent(
          value, newSelection, SelectionChangedCause.keyboard),
    );
    if (state._value.selection == newSelection) {
      _horizontalMovementRun = currentRun;
      _runSelection = newSelection;
    }
  }

  @override
  bool get isActionEnabled => state._value.selection.isValid;
}

class _SelectAllAction extends ContextAction<SelectAllTextIntent> {
  _SelectAllAction(this.state);

  final MongolEditableTextState state;

  @override
  Object? invoke(SelectAllTextIntent intent, [BuildContext? context]) {
    return Actions.invoke(
      context!,
      UpdateSelectionIntent(
        state._value,
        TextSelection(baseOffset: 0, extentOffset: state._value.text.length),
        intent.cause,
      ),
    );
  }

  @override
  bool get isActionEnabled => state.widget.selectionEnabled;
}

class _CopySelectionAction extends ContextAction<CopySelectionTextIntent> {
  _CopySelectionAction(this.state);

  final MongolEditableTextState state;

  @override
  void invoke(CopySelectionTextIntent intent, [BuildContext? context]) {
    if (intent.collapseSelection) {
      state.cutSelection(intent.cause);
    } else {
      state.copySelection(intent.cause);
    }
  }

  @override
  bool get isActionEnabled =>
      state._value.selection.isValid && !state._value.selection.isCollapsed;
}