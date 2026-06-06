"""
Migration: 0001_initial
Generated: 2026-06-06T17:07:57.478202+00:00

Auto-generated migration file. Review before applying.
"""

from surreal_orm.migrations import Migration
from surreal_orm.migrations.operations import (
    AddField,
    CreateTable,
)

migration = Migration(
    name="0001_initial",
    dependencies=[],
    operations=[
        CreateTable(name='trip', table_type='normal'),
        AddField(table='trip', name='start_time', field_type='datetime'),
        AddField(table='trip', name='start_location', field_type='any'),
        AddField(table='trip', name='end_time', field_type='datetime'),
        AddField(table='trip', name='end_location', field_type='any'),
        AddField(table='trip', name='activities', field_type='array<any>'),
        CreateTable(name='RouteStep', table_type='normal'),
        AddField(table='RouteStep', name='type', field_type='any'),
        AddField(table='RouteStep', name='name', field_type='string'),
        AddField(table='RouteStep', name='description', field_type='string'),
        AddField(table='RouteStep', name='duration', field_type='float'),
        AddField(table='RouteStep', name='area', field_type='any'),
        AddField(table='RouteStep', name='path', field_type='any'),
        AddField(table='RouteStep', name='location', field_type='any'),
        CreateTable(name='route', table_type='normal'),
        AddField(table='route', name='name', field_type='string'),
        AddField(table='route', name='trip_id', field_type='string'),
        AddField(table='route', name='steps', field_type='array<any>'),
    ],
)
