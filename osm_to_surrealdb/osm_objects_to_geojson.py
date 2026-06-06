"""
Extract object-like OSM features as GeoJSON points.

The output is intended for POIs and physical objects such as shops, amenities,
tourism features, viewpoints, peaks and similar tagged objects. Roads, routes,
boundaries and other geometry-heavy features are skipped. Area objects are
written as representative points instead of polygons.
"""
import argparse
import json
import sys

import osmium

try:
    import shapely.wkb as wkblib
except ImportError:  # pragma: no cover - depends on optional example dependency
    wkblib = None


wkbfab = osmium.geom.WKBFactory()


# Tags that usually describe a real-world object or POI rather than geometry.
OBJECT_KEYS = {
    'aerialway',
    'amenity',
    'barrier',
    'craft',
    'emergency',
    'geological',
    'healthcare',
    'historic',
    'information',
    'leisure',
    'man_made',
    'military',
    'natural',
    'office',
    'place_of_worship',
    'power',
    'public_transport',
    'railway',
    'shop',
    'sport',
    'tourism',
}


# Tags that normally describe lines, polygons or administrative/network data.
GEOMETRY_KEYS = {
    'boundary',
    'highway',
    'junction',
    'landuse',
    'place',
    'route',
    'type',
    'waterway',
}


# Values that are commonly mapped as surfaces or lines, even when they use a
# generally object-like key.
GEOMETRY_VALUES = {
    'aerialway': {
        'cable_car',
        'chair_lift',
        'drag_lift',
        'gondola',
        'goods',
        'mixed_lift',
        'platter',
        'rope_tow',
        't-bar',
    },
    'man_made': {
        'breakwater',
        'bridge',
        'cutline',
        'dyke',
        'embankment',
        'groyne',
        'pipeline',
        'pier',
    },
    'natural': {
        'bare_rock',
        'bay',
        'beach',
        'coastline',
        'fell',
        'glacier',
        'grassland',
        'heath',
        'mud',
        'reef',
        'ridge',
        'sand',
        'scree',
        'scrub',
        'shingle',
        'strait',
        'tree_row',
        'valley',
        'water',
        'wetland',
        'wood',
    },
    'railway': {
        'abandoned',
        'construction',
        'disused',
        'funicular',
        'light_rail',
        'miniature',
        'monorail',
        'narrow_gauge',
        'platform',
        'preserved',
        'rail',
        'subway',
        'tram',
    },
}


# These keys are useful metadata but should not make an object interesting alone.
METADATA_KEYS = {
    'addr:city',
    'addr:country',
    'addr:floor',
    'addr:full',
    'addr:housename',
    'addr:housenumber',
    'addr:postcode',
    'addr:street',
    'addr:unit',
    'building',
    'building:levels',
    'created_by',
    'description',
    'email',
    'fee',
    'fixme',
    'image',
    'level',
    'name',
    'note',
    'opening_hours',
    'operator',
    'phone',
    'source',
    'start_date',
    'website',
    'wheelchair',
    'wikidata',
    'wikipedia',
}


class ObjectGeoJsonWriter(osmium.SimpleHandler):

    def __init__(self, output, include_areas=True, all_tagged_nodes=False):
        super().__init__()
        self.output = output
        self.include_areas = include_areas
        self.all_tagged_nodes = all_tagged_nodes
        self.first = True

        self.output.write('{"type": "FeatureCollection", "features": [\n')

    def finish(self):
        self.output.write('\n]}\n')

    def node(self, n):
        tags = dict(n.tags)

        if not n.location.valid() or not self.is_object(tags, is_node=True):
            return

        self.write_feature(
            'node',
            n.id,
            tags,
            {
                'type': 'Point',
                'coordinates': [n.location.lon, n.location.lat],
            },
        )

    def area(self, a):
        if not self.include_areas:
            return

        tags = dict(a.tags)
        if not self.is_object(tags, is_node=False):
            return

        if wkblib is None:
            raise RuntimeError("Area point extraction requires shapely.")

        wkb = wkbfab.create_multipolygon(a)
        point = wkblib.loads(wkb, hex=True).representative_point()

        self.write_feature(
            'area',
            a.id,
            tags,
            {
                'type': 'Point',
                'coordinates': [point.x, point.y],
            },
        )

    def is_object(self, tags, is_node):
        if not tags:
            return False

        if GEOMETRY_KEYS.intersection(tags):
            return False

        for key, values in GEOMETRY_VALUES.items():
            if tags.get(key) in values:
                return False

        if OBJECT_KEYS.intersection(tags):
            return True

        if is_node and self.all_tagged_nodes:
            return any(key not in METADATA_KEYS for key in tags)

        return False

    def write_feature(self, osm_type, osm_id, tags, geometry):
        properties = {
            'osm_type': osm_type,
            'osm_id': osm_id,
        }
        properties.update(tags)

        feature = {
            'type': 'Feature',
            'geometry': geometry,
            'properties': properties,
        }

        if self.first:
            self.first = False
        else:
            self.output.write(',\n')

        json.dump(feature, self.output, ensure_ascii=False, separators=(',', ':'))


def main(osmfile, outfile=None, include_areas=True, all_tagged_nodes=False):
    output = sys.stdout if outfile is None else open(outfile, 'w', encoding='utf-8')

    try:
        handler = ObjectGeoJsonWriter(output, include_areas, all_tagged_nodes)
        handler.apply_file(osmfile)
        handler.finish()
    finally:
        if outfile is not None:
            output.close()

    return 0


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('osmfile', help='OSM input file, for example .osm.pbf')
    parser.add_argument('-o', '--output', help='GeoJSON output file. Defaults to stdout.')
    parser.add_argument(
        '--nodes-only',
        action='store_true',
        help='Only emit tagged object nodes. Do not emit representative points for areas.',
    )
    parser.add_argument(
        '--all-tagged-nodes',
        action='store_true',
        help='Also emit tagged nodes that are not matched by the built-in object key list.',
    )
    return parser.parse_args()


if __name__ == '__main__':
    args = parse_args()
    sys.exit(main(args.osmfile, args.output, not args.nodes_only, args.all_tagged_nodes))
