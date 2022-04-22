import 'package:adaptive_dialog/adaptive_dialog.dart';
import 'package:every_door/helpers/equirectangular.dart';
import 'package:every_door/models/address.dart';
import 'package:every_door/widgets/address_form.dart';
import 'package:every_door/widgets/radio_field.dart';
import 'package:every_door/models/amenity.dart';
import 'package:every_door/providers/changes.dart';
import 'package:every_door/providers/need_update.dart';
import 'package:every_door/providers/osm_data.dart';
import 'package:every_door/screens/editor.dart';
import 'package:flutter/material.dart';
import 'package:every_door/constants.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:latlong2/latlong.dart' show LatLng;

class BuildingEditorPane extends ConsumerStatefulWidget {
  final OsmChange? building;
  final LatLng location;

  const BuildingEditorPane({this.building, required this.location});

  @override
  ConsumerState<BuildingEditorPane> createState() => _BuildingEditorPaneState();
}

class _BuildingEditorPaneState extends ConsumerState<BuildingEditorPane> {
  late final OsmChange building;
  bool manualLevels = false;
  List<String> nearestStreets = [];
  List<String> nearestPlaces = [];
  List<String> nearestCities = [];
  List<String> nearestLevels = [];

  @override
  void initState() {
    super.initState();
    building = widget.building?.copy() ??
        OsmChange.create(tags: {'building': 'yes'}, location: widget.location);
    updateStreets();
    updateLevels();
  }

  List<String> _filterDuplicates(Iterable<String?> source) {
    final values = <String>{};
    final result = source.whereType<String>().toList();
    result.retainWhere((element) => values.add(element));
    return result;
  }

  updateStreets() async {
    final provider = ref.read(osmDataProvider);
    final addrs = await provider.getAddressesAround(widget.location, limit: 30);
    setState(() {
      nearestStreets = _filterDuplicates(addrs.map((e) => e.street));
      nearestPlaces = _filterDuplicates(addrs.map((e) => e.place));
      nearestCities = _filterDuplicates(addrs.map((e) => e.city));
    });
  }

  updateLevels() async {
    // TODO: wtf is this mess?! Simplify.
    final provider = ref.read(osmDataProvider);
    const radius = kVisibilityRadius;
    List<OsmChange> data = await provider.getElements(widget.location, radius);
    final levelCount = <int, int>{};
    const distance = DistanceEquirectangular();
    data
        .where((e) =>
            distance(widget.location, e.location) <= radius &&
            e['building:levels'] != null)
        .forEach((e) {
      final levels = int.tryParse(e['building:levels']!);
      if (levels != null) {
        levelCount[levels] = (levelCount[levels] ?? 0) + 1;
      }
    });
    levelCount.remove(1);
    levelCount.remove(2);
    if (levelCount.isEmpty) return;

    final values = levelCount.entries.toList();
    values.sort((a, b) => b.value.compareTo(a.value));

    final nearestInt = values.map((e) => e.key).toList();
    if (nearestInt.length > 2) nearestInt.removeRange(2, nearestInt.length);
    nearestInt.sort();

    setState(() {
      nearestLevels = nearestInt.map((e) => e.toString()).toList();
    });
  }

  bool validateLevels(String? value) {
    if (value == null || value.trim().isEmpty) return true;
    final levels = int.tryParse(value.trim());
    if (levels == null) return false;
    return levels >= 1 && levels <= 40;
  }

  saveAndClose() {
    building.removeTag(OsmChange.kCheckedKey);
    final changes = ref.read(changesProvider);
    changes.saveChange(building);
    ref.read(needMapUpdateProvider).trigger();
    Navigator.pop(context);
  }

  deleteAndClose() {
    if (building.isNew) {
      final changes = ref.read(changesProvider);
      changes.deleteChange(building);
      ref.read(needMapUpdateProvider).trigger();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    final levelOptions = ['1', '2'] + nearestLevels;
    if (building['building:levels'] == null)
      levelOptions.add(kManualOption);

    return Column(
      children: [
        AddressForm(
          location: widget.location,
          initialAddress: StreetAddress.fromTags(building.getFullTags()),
          autoFocus: building['addr:housenumber'] == null,
          onChange: (addr) {
            addr.setTags(building);
          },
        ),
        Table(
          columnWidths: const {
            0: FixedColumnWidth(100.0),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: Text('Levels', style: kFieldTextStyle),
                ),
                if (!manualLevels)
                  RadioField(
                    // TODO: get levels around and add two
                    options: levelOptions,
                    value: building['building:levels'],
                    onChange: (value) {
                      setState(() {
                        if (value == kManualOption) {
                          manualLevels = true;
                        } else {
                          building['building:levels'] = value;
                        }
                      });
                    },
                  ),
                if (manualLevels)
                  TextFormField(
                    keyboardType: TextInputType.number,
                    style: kFieldTextStyle,
                    initialValue: building['building:levels'],
                    autofocus: building['addr:housenumber'] != null &&
                        building['building:levels'] == null,
                    validator: (value) =>
                        validateLevels(value) ? null : 'Please enter a number',
                    onChanged: (value) {
                      setState(() {
                        building['building:levels'] = value.trim();
                      });
                    },
                  ),
              ],
            ),
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: Text('Roof levels', style: kFieldTextStyle),
                ),
                RadioField(
                    options: const ['1', '2', '3'],
                    value: building['roof:levels'],
                    onChange: (value) {
                      setState(() {
                        building['roof:levels'] = value;
                      });
                    })
              ],
            ),
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: Text('Roof Shape', style: kFieldTextStyle),
                ),
                RadioField(
                  // TODO: labels
                  options: const ['flat', 'gabled', 'hipped', 'pyramidal'],
                  value: building['roof:shape'],
                  onChange: (value) {
                    setState(() {
                      building['roof:shape'] = value;
                    });
                  },
                ),
              ],
            ),
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: Text('Type', style: kFieldTextStyle),
                ),
                RadioField(
                  // TODO: labels
                  options: const [
                    'house',
                    'apartments',
                    'retail',
                    'commercial',
                    'shed',
                    'industrial'
                  ],
                  value: building['building'] == 'yes'
                      ? null
                      : building['building'],
                  onChange: (value) {
                    setState(() {
                      building['building'] = value ?? 'yes';
                    });
                  },
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (context) => PoiEditorPage(amenity: building)),
                );
              },
              child: Text('MORE...'),
            ),
            if (building.isNew)
              TextButton(
                child:
                    Text(loc.editorDeleteButton), // TODO: does the label fit?
                onPressed: () async {
                  final answer = await showOkCancelAlertDialog(
                    context: context,
                    title:
                        loc.editorDeleteTitle('building'), // TODO: better msg
                    okLabel: loc.editorDeleteButton,
                    isDestructiveAction: true,
                  );
                  if (answer == OkCancelResult.ok) {
                    deleteAndClose();
                  }
                },
              ),
            Expanded(child: Container()),
            TextButton(
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
            TextButton(
              child: Text(MaterialLocalizations.of(context).okButtonLabel),
              onPressed: () {
                if (true) {
                  saveAndClose();
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}
