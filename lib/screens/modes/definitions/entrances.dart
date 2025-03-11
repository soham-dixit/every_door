import 'package:country_coder/country_coder.dart';
import 'package:every_door/helpers/multi_icon.dart';
import 'package:every_door/helpers/tags/element_kind.dart';
import 'package:every_door/models/amenity.dart';
import 'package:every_door/models/plugin.dart';
import 'package:every_door/models/preset.dart';
import 'package:every_door/providers/location.dart';
import 'package:every_door/providers/presets.dart';
import 'package:every_door/screens/editor.dart';
import 'package:every_door/screens/editor/building.dart';
import 'package:every_door/screens/editor/entrance.dart';
import 'package:every_door/screens/modes/definitions/base.dart';
import 'package:every_door/widgets/entrance_markers.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

abstract class EntrancesModeDefinition extends BaseModeDefinition {
  List<OsmChange> nearest = [];
  LatLng? newLocation;

  List<ElementKindImpl> _kinds = [
    ElementKind.entrance,
    ElementKind.building,
    ElementKind.address,
  ];

  EntrancesModeDefinition(super.ref);

  @override
  String get name => "entrances";

  @override
  MultiIcon getIcon(BuildContext context, bool outlined) {
    final loc = AppLocalizations.of(context)!;
    return MultiIcon(
      fontIcon: !outlined ? Icons.home : Icons.home_outlined,
      tooltip: loc.navEntrancesMode,
    );
  }

  ElementKindImpl getOurKind(OsmChange element) =>
      ElementKind.matchChange(element, _kinds);

  @override
  bool isOurKind(OsmChange element) =>
      getOurKind(element) != ElementKind.unknown;

  @override
  Future<void> updateNearest() async {
    nearest = await super.getNearestChanges();
    notifyListeners();
  }

  double get adjustZoomPrimary => 0.0;

  double get adjustZoomSecondary => 0.0;

  SizedMarker? buildMarker(OsmChange element);

  MultiIcon? getButton(BuildContext context, bool isPrimary);

  void openEditor({
    required BuildContext context,
    OsmChange? element,
    LatLng? location,
    bool? isPrimary,
  });

  Widget disambiguationLabel(BuildContext context, OsmChange element) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Text(element.typeAndName, style: TextStyle(fontSize: 20.0)),
    );
  }

  @override
  void updateFromJson(Map<String, dynamic> data, Plugin plugin) {
    _kinds = parseKinds(data['kinds']) ?? parseKinds(data['kind']) ?? _kinds;
  }
}

class DefaultEntrancesModeDefinition extends EntrancesModeDefinition {
  bool buildingsNeedAddresses = false;

  DefaultEntrancesModeDefinition(super.ref);

  @override
  String get name => "entrances";

  @override
  double get adjustZoomSecondary => 0.7;

  @override
  Future<void> updateNearest({LatLng? forceLocation, int? forceRadius}) async {
    final LatLng location =
        forceLocation ?? ref.read(effectiveLocationProvider);

    final nearest = await super.getNearestChanges(
        forceLocation: forceLocation, forceRadius: forceRadius);

    // Sort by buildings, addresses, entrances
    int indexKind(OsmChange change) {
      final kind = getOurKind(change);
      if (kind == ElementKind.building) return 0;
      if (kind == ElementKind.address) return 1;
      if (kind == ElementKind.entrance) return 2;
      return 3;
    }

    nearest.sort((a, b) => indexKind(a).compareTo(indexKind(b)));

    // Wait for country coder
    if (!CountryCoder.instance.ready) {
      await Future.doWhile(() => Future.delayed(Duration(milliseconds: 100))
          .then((_) => !CountryCoder.instance.ready));
    }

    buildingsNeedAddresses = !CountryCoder.instance.isIn(
      lat: location.latitude,
      lon: location.longitude,
      inside: 'Q55', // Netherlands
    );

    this.nearest = nearest;
    notifyListeners();
  }

  static const kBuildingNeedsAddress = {
    'yes',
    'house',
    'residential',
    'detached',
    'apartments',
    'terrace',
    'commercial',
    'school',
    'semidetached_house',
    'retail',
    'construction',
    'farm',
    'church',
    'office',
    'civic',
    'university',
    'public',
    'hospital',
    'hotel',
    'chapel',
    'kindergarten',
    'mosque',
    'dormitory',
    'train_station',
    'college',
    'semi',
    'temple',
    'government',
    'supermarket',
    'fire_station',
    'sports_centre',
    'shop',
    'stadium',
    'religious',
  };

  String makeBuildingLabel(OsmChange building) {
    const kMaxNumberLength = 6;
    final needsAddress = buildingsNeedAddresses &&
        (building['building'] == null ||
            kBuildingNeedsAddress.contains(building['building']));
    String number = building['addr:housenumber'] ??
        building['addr:housename'] ??
        (needsAddress ? '?' : '');
    if (number.length > kMaxNumberLength) {
      final spacePos = number.indexOf(' ');
      if (spacePos > 0) number = number.substring(0, spacePos);
      if (number.length > kMaxNumberLength)
        number = number.substring(0, kMaxNumberLength - 1);
      number = number + '…';
    }

    return number;
  }

  @override
  SizedMarker buildMarker(OsmChange element) {
    final kind = getOurKind(element);
    if (kind == ElementKind.building) {
      final isComplete = element['building:levels'] != null;
      return BuildingMarker(
        label: makeBuildingLabel(element),
        isComplete: isComplete,
      );
    } else if (kind == ElementKind.address) {
      return AddressMarker(
        label: makeBuildingLabel(element),
      );
    } else {
      // entrance
      const kNeedsData = {'staircase', 'yes'};
      final isComplete = (kNeedsData.contains(element['entrance'])
              ? (element['addr:flats'] ?? element['addr:unit']) != null
              : true) &&
          element['entrance'] != 'yes';
      return EntranceMarker(
        isComplete: isComplete,
      );
    }
  }

  @override
  MultiIcon? getButton(BuildContext context, bool isPrimary) {
    final loc = AppLocalizations.of(context)!;
    if (isPrimary) {
      return MultiIcon(
        fontIcon: Icons.house,
        tooltip: loc.entrancesAddBuilding,
      );
    } else {
      return MultiIcon(
        fontIcon: Icons.sensor_door,
        tooltip: loc.entrancesAddEntrance,
      );
    }
  }

  @override
  void openEditor({
    required BuildContext context,
    OsmChange? element,
    LatLng? location,
    bool? isPrimary,
  }) async {
    final LatLng loc =
        location ?? element?.location ?? ref.read(effectiveLocationProvider);
    Widget pane;
    // TODO: how do we create one?
    if (isPrimary != null && !isPrimary ||
        (element != null && ElementKind.entrance.matchesChange(element))) {
      pane = EntranceEditorPane(entrance: element, location: loc);
    } else {
      pane = BuildingEditorPane(building: element, location: loc);
    }

    if (location != null) {
      newLocation = location;
      notifyListeners();
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => pane,
    );
    newLocation = null;
    notifyListeners();
  }

  @override
  Widget disambiguationLabel(BuildContext context, OsmChange element) {
    final loc = AppLocalizations.of(context)!;
    final kind = getOurKind(element);

    String label;
    if (kind == ElementKind.building) {
      label = loc
          .buildingX(
              element["addr:housenumber"] ?? element["addr:housename"] ?? '')
          .trim();
    } else if (kind == ElementKind.address) {
      final value = [element['ref'], element['addr:flats']]
          .whereType<String>()
          .join(': ');
      label = loc.entranceX(value).trim();
    } else if (kind == ElementKind.entrance) {
      // entrance
      final value = [element['ref'], element['addr:flats']]
          .whereType<String>()
          .join(': ');
      label = loc.entranceX(value).trim();
    } else {
      label = element.typeAndName;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Text(label, style: TextStyle(fontSize: 20.0)),
    );
  }
}

class EntrancesModeCustom extends EntrancesModeDefinition {
  final String _name;
  MultiIcon? _icon;
  MultiIcon? _iconOutlined;
  MultiIcon? _primary;
  MultiIcon? _secondary;
  String? _primaryPreset;
  String? _secondaryPreset;
  double? _zoomPrimary;
  double? _zoomSecondary;
  Map<String, dynamic> _rendering = const {};
  final Map<String, MultiIcon> _markerIcons = {};

  EntrancesModeCustom({
    required ref,
    required String name,
    required Map<String, dynamic> data,
    required Plugin plugin,
  })  : _name = name,
        super(ref) {
    super.updateFromJson(data, plugin);

    _rendering = data['markers'] ?? const {};

    final modeIconName = data['icon'];
    if (modeIconName != null) {
      _icon = plugin.loadIcon(modeIconName, data['name'] ?? _name);
      if (data.containsKey('iconOutlined')) {
        _iconOutlined =
            plugin.loadIcon(data['iconOutlined']!, data['name'] ?? _name);
      }
    }

    final Map<String, dynamic>? primary = data['primary'];
    if (primary != null) {
      _zoomPrimary = primary['adjustZoom'];
      _primaryPreset = primary['preset'];
      final iconName = primary['icon'];
      if (iconName != null) {
        _primary = plugin.loadIcon(iconName, primary['tooltip']);
      }
    }

    final Map<String, dynamic>? secondary = data['secondary'];
    if (secondary != null) {
      _zoomSecondary = secondary['adjustZoom'];
      _secondaryPreset = secondary['preset'];
      final iconName = secondary['icon'];
      if (iconName != null) {
        _secondary = plugin.loadIcon(iconName, secondary['tooltip']);
      }
    }

    // Cache icons, because later we won't have access to the plugin data.
    _rendering.forEach((k, data) {
      if (data is Map<String, dynamic> && data.containsKey('icon')) {
        _markerIcons['$k.icon'] = plugin.loadIcon(data['icon']!);
        if (data.containsKey('iconPartial')) {
          _markerIcons['$k.partial'] = plugin.loadIcon(data['iconPartial']!);
        }
      }
    });
  }

  @override
  String get name => _name;

  @override
  double get adjustZoomPrimary => _zoomPrimary ?? 0.0;

  @override
  double get adjustZoomSecondary => _zoomSecondary ?? 0.0;

  @override
  MultiIcon getIcon(BuildContext context, bool outlined) {
    return (!outlined ? _icon : _iconOutlined ?? _icon) ??
        super.getIcon(context, outlined);
  }

  @override
  SizedMarker? buildMarker(OsmChange element) {
    final kind = ElementKind.matchChange(element, _kinds);
    final data = _rendering[kind.name] as Map<String, dynamic>?;
    if (data != null) {
      final isComplete = (data['requiredKeys'] as List<dynamic>?)
              ?.every((k) => element[k] != null) ??
          false;
      final String? icon = data['icon'];
      final String? labelTemplate = data['label'];
      if (icon != null) {
        final defaultIcon = _markerIcons['${kind.name}.icon']!;
        final ourIcon = isComplete
            ? defaultIcon
            : _markerIcons['${kind.name}.partial'] ?? defaultIcon;
        return IconMarker(ourIcon);
      } else if (labelTemplate != null) {
        final re = RegExp(r'\{([^}]+)\}');
        final label =
            labelTemplate.replaceAllMapped(re, (m) => element[m[1]!] ?? '?');
        return BuildingMarker(isComplete: isComplete, label: label);
      } else {
        return EntranceMarker(isComplete: isComplete);
      }
    }
    return null;
  }

  @override
  MultiIcon? getButton(BuildContext context, bool isPrimary) {
    return isPrimary ? _primary : _secondary;
  }

  @override
  void openEditor({
    required BuildContext context,
    OsmChange? element,
    LatLng? location,
    bool? isPrimary,
  }) async {
    Preset? preset;
    if (element == null) {
      final presetName = isPrimary ?? true ? _primaryPreset : _secondaryPreset;
      if (presetName == null) return;
      final locale = Localizations.localeOf(context);
      final presets = await ref
          .read(presetProvider)
          .getPresetsById([presetName], locale: locale);
      if (presets.isEmpty) return;
      preset = presets.first;
    }

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PoiEditorPage(
          amenity: element,
          location: location,
          preset: preset,
        ),
        fullscreenDialog: true,
      ),
    );
  }
}
