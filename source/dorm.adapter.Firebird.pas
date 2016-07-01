{ *******************************************************************************
  Copyright 2010-2011 Daniele Teti

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
  ******************************************************************************** }

unit dorm.adapter.Firebird;

interface

uses
  dorm.Commons,
  classes,
  SysUtils,
  DB,
  SqlExpr,
  dorm.adapter.DBExpress.Factory,
  DBXClient,
  DBXCommon,
  dbclient,
  dbxfirebird,
  Rtti,
  dorm,
  superobject,
  TypInfo,
  FMTBcd,
  dorm.Collections;

type
  TFirebirdPersistStrategy = class(TdormInterfacedObject, IdormPersistStrategy)
  strict protected
    FB: TDBXFactory;
    FLogger: IdormLogger;
    FCurTransaction: TDBXTransaction;
    FKeysGeneratorClassName: string;
    FKeysGenerator: IdormKeysGenerator;
    FKeyType: TdormKeyType;
    FNullKeyValue: TValue;
    FLastInsertOID: TValue;
    function CreateDBXFactory(Conf: ISuperObject): TDBXFactory; virtual;
    function CreateObjectFromDBXReader(ARttiType: TRttiType;
      AReader: TDBXReader; AFieldsMapping: TArray<TdormFieldMapping>): TObject;
    function LoadObjectFromDBXReader(ARttiType: TRttiType; AReader: TDBXReader;
      AFieldsMapping: TArray<TdormFieldMapping>; AObject: TObject): Boolean;
    function GetLogger: IdormLogger;
    procedure SetDBXParameterValue(aFieldType: string;
      aParameter: TDBXParameter; aValue: TValue);
    procedure SetDBXValue(aFieldType: string; aDBXValue: TDBXWritableValue;
      aValue: TValue);
  public
    function GenerateAndFillPrimaryKeyParam(PKParam: TDBXParameter;
      const Entity: string): TValue; overload;
    function FillPrimaryKeyParam(PKParam: TDBXParameter;
      const Value: TValue): TValue;
    function EscapeString(const Value: String): String;
    function EscapeDate(const Value: TDate): String;
    function EscapeDateTime(const Value: TDate): String;
    function GetLastInsertOID: TValue;
    function GetKeysGenerator: IdormKeysGenerator;
    function Insert(ARttiType: TRttiType; AObject: TObject; ATableName: string;
      AFieldsMapping: TArray<TdormFieldMapping>): TValue;
    function Update(ARttiType: TRttiType; AObject: TObject; ATableName: string;
      AFieldsMapping: TArray<TdormFieldMapping>): TValue;
    function Load(ARttiType: TRttiType; ATableName: string;
      AFieldsMapping: TArray<TdormFieldMapping>; const Value: TValue)
      : TObject; overload;
    function List(ARttiType: TRttiType; ATableName: string;
      AFieldsMapping: TArray<TdormFieldMapping>;
      AdormSearchCriteria: IdormSearchCriteria): TdormCollection; overload;
    // function CreateChildLoaderSearch(AChildClassTypeInfo: PTypeInfo;
    // AChildClassName, AChildTableName, AChildRelationField: string;
    // APKValue: TValue): IdormSearchCriteria;
    function Delete(ARttiType: TRttiType; AObject: TObject; ATableName: string;
      AFieldsMapping: TArray<TdormFieldMapping>): TObject;
    procedure DeleteAll(ATableName: string);
    function Count(ATableName: string): Int64;
    procedure ConfigureStrategy(ConfigurationInfo: ISuperObject); virtual;
    procedure InitStrategy;
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function InTransaction: Boolean;
    procedure SetLogger(ALogger: IdormLogger);
    destructor Destroy; override;
    class procedure register;
    function IsNullKey(const Value: TValue): Boolean;
    function GetNullKeyValue: TValue;
    function GetKeyType: TdormKeyType;
    function RawExecute(SQL: string): Int64;
    function ExecuteAndGetFirst(SQL: string): Int64;
  end;

  TFirebirdTableSequence = class(TdormInterfacedObject, IdormKeysGenerator)
  private
    FPersistStrategy: IdormPersistStrategy;
  public
    function NewStringKey(const Entity: string): string;
    function NewIntegerKey(const Entity: string): UInt64;
    procedure SetPersistStrategy(const PersistentStrategy
      : IdormPersistStrategy);
    class procedure RegisterClass;
  end;

implementation

uses
  dorm.Utils;

function TFirebirdPersistStrategy.Update(ARttiType: TRttiType; AObject: TObject;
  ATableName: string; AFieldsMapping: TArray<TdormFieldMapping>): TValue;
var
  field: TdormFieldMapping;
  SQL: string;
  Query: TDBXCommand;
  I, pk_idx: Integer;
  v: TValue;
  sql_fields_names: string;
  pk_field: string;
begin
  sql_fields_names := '';
  for field in AFieldsMapping do
    if not field.pk then
      sql_fields_names := sql_fields_names + ',"' + field.field + '" = ?';
  System.Delete(sql_fields_names, 1, 1);

  pk_field := AFieldsMapping[GetPKMappingIndex(AFieldsMapping)].field;
  SQL := Format('UPDATE %S SET %S WHERE %S = ?', [ATableName, sql_fields_names,
    pk_field]);

  GetLogger.Debug(AFieldsMapping[GetPKMappingIndex(AFieldsMapping)].field);

  GetLogger.Debug('PREPARING: ' + SQL);
  Query := FB.Prepare(SQL);
  try
    I := 0;
    for field in AFieldsMapping do
    begin
      v := TdormUtils.GetField(AObject, field.name);

      if field.pk then
        Continue
      else
      begin
        SetDBXParameterValue(field.field_type, Query.Parameters[I], v);
      end;
      inc(I);
    end;
    pk_idx := GetPKMappingIndex(AFieldsMapping);

    v := ARttiType.GetProperty(AFieldsMapping[pk_idx].name).GetValue(AObject);
    FillPrimaryKeyParam(Query.Parameters[I], v);
    GetLogger.Debug('EXECUTING PREPARED: ' + SQL);
    FB.Execute(Query);
  finally
    Query.Free;
  end;
end;

procedure TFirebirdPersistStrategy.Commit;
begin
  if not assigned(FCurTransaction) then
    raise Exception.Create('Transaction is not active');
  FB.GetConnection.CommitFreeAndNil(FCurTransaction);
end;

procedure TFirebirdPersistStrategy.ConfigureStrategy(ConfigurationInfo
  : ISuperObject);
var
  ctx: TRttiContext;
  t: TRttiType;
  obj: TObject;
begin
  FB := CreateDBXFactory(ConfigurationInfo);
  FKeysGeneratorClassName := ConfigurationInfo.S['keys_generator'];
  t := ctx.FindType(FKeysGeneratorClassName);
  if t = nil then
    raise EdormException.Create('Unknown key generator ' +
      FKeysGeneratorClassName);
  obj := t.AsInstance.MetaclassType.Create;
  if not Supports(obj, IdormKeysGenerator, FKeysGenerator) then
    raise EdormException.Create('Keys generator ' + FKeysGeneratorClassName +
      ' doesn''t implements ''IdormKeysGenerator''');
  FKeysGenerator.SetPersistStrategy(self);
  self._Release;

  if (SameText(ConfigurationInfo.S['key_type'], 'integer')) then
  begin
    FKeyType := ktInteger;
    FNullKeyValue := ConfigurationInfo.I['null_key_value']
  end
  else if (SameText(ConfigurationInfo.S['key_type'], 'string')) then
  begin
    FKeyType := ktString;
    FNullKeyValue := ConfigurationInfo.S['null_key_value']
  end
  else
    raise EdormException.Create('Unknown key type');
  inherited;
end;

function TFirebirdPersistStrategy.Count(ATableName: string): Int64;
var
  cmd: TDBXCommand;
  reader: TDBXReader;
  SQL: string;
begin
  Result := -1;
  SQL := 'SELECT COUNT(*) FROM ' + ATableName;
  GetLogger.Debug('PREPARING: ' + SQL);
  cmd := FB.Prepare(SQL);
  try
    reader := cmd.ExecuteQuery;
    try
      if reader.Next then
        Result := reader.Value[0].AsInt64;
    finally
      reader.Free;
    end;
  finally
    cmd.Free;
  end;
end;

// function TFirebirdPersistStrategy.CreateChildLoaderSearch(AChildClassTypeInfo
// : PTypeInfo; AChildClassName, AChildTableName, AChildRelationField: string;
// APKValue: TValue): IdormSearchCriteria;
// var
// SQL: string;
// begin
// SQL := 'SELECT * FROM ' + AChildTableName + ' WHERE ' +
// AChildRelationField + ' = ';
// case FKeyType of
// ktInteger:
// SQL := SQL + IntToStr(APKValue.AsInt64);
// ktString:
// SQL := SQL + '''' + StringReplace(APKValue.AsString, '''', '''''',
// [rfReplaceAll]) + '''';
// end;
//
// GetLogger.Debug('CreateChildLoaderSearch: ' + SQL);
// Result := TdormSimpleSearchCriteria.Create(nil, SQL);
// end;

function TFirebirdPersistStrategy.CreateDBXFactory(Conf: ISuperObject)
  : TDBXFactory;
begin
  Result := TDBXFactory.Create('dbxfb.dll', 'firebird', Conf);
end;

function TFirebirdPersistStrategy.Delete(ARttiType: TRttiType; AObject: TObject;
  ATableName: string; AFieldsMapping: TArray<TdormFieldMapping>): TObject;
var
  pk_idx: Integer;
  pk_value: TValue;
  pk_attribute_name, pk_field_name, SQL: string;
  cmd: TDBXCommand;
begin
  pk_idx := GetPKMappingIndex(AFieldsMapping);
  if pk_idx = -1 then
    raise Exception.Create('Invalid primary key for table ' + ATableName);
  pk_attribute_name := AFieldsMapping[pk_idx].name;
  pk_field_name := AFieldsMapping[pk_idx].field;
  pk_value := ARttiType.GetProperty(pk_attribute_name).GetValue(AObject);
  SQL := 'DELETE FROM ' + ATableName + ' WHERE ' + pk_field_name + ' = ?';
  GetLogger.Debug('PREPARING: ' + SQL);
  cmd := FB.Prepare(SQL);
  try
    FillPrimaryKeyParam(cmd.Parameters[pk_idx], pk_value);
    GetLogger.Debug('EXECUTING PREPARED: ' + SQL);
    cmd.ExecuteUpdate;
  finally
    cmd.Free;
  end;

end;

procedure TFirebirdPersistStrategy.DeleteAll(ATableName: string);
var
  SQL: string;
begin
  SQL := 'DELETE FROM ' + ATableName;
  GetLogger.Debug('EXECUTING :' + SQL);
  FB.Execute(SQL);
end;

destructor TFirebirdPersistStrategy.Destroy;
begin
  FB.Free;
  inherited;
end;

function TFirebirdPersistStrategy.EscapeDate(const Value: TDate): String;
begin
  Result := FormatDateTime('YYYY-MM-DD', Value);
end;

function TFirebirdPersistStrategy.EscapeDateTime(const Value: TDate): String;
begin
  Result := FormatDateTime('YYYY-MM-DD HH:NN:SS', Value);
end;

function TFirebirdPersistStrategy.EscapeString(const Value: String): String;
begin
  Result := StringReplace(Value, '''', '''''', [rfReplaceAll]);
end;

function TFirebirdPersistStrategy.ExecuteAndGetFirst(SQL: string): Int64;
var
  rdr: TDBXReader;
  cmd: TDBXCommand;
begin
  cmd := FB.Prepare(SQL);
  try
    rdr := cmd.ExecuteQuery;
    try
      if rdr.Next then
        Result := rdr.Value[0].AsInt64
      else
        raise EdormException.Create('ExecuteAndGetFirst returns o rows');
      rdr.Close;
    finally
      rdr.Free;
    end;
  finally
    cmd.Free;
  end;
end;

function TFirebirdPersistStrategy.GenerateAndFillPrimaryKeyParam
  (PKParam: TDBXParameter; const Entity: string): TValue;
begin
  case FKeyType of
    ktString:
      begin
        PKParam.Value.SetString(FKeysGenerator.NewStringKey(Entity));
        Result := PKParam.Value.GetString;
      end;
    ktInteger:
      begin
        PKParam.Value.AsInt64 := FKeysGenerator.NewIntegerKey(Entity);
        Result := PKParam.Value.AsInt64;
      end;
  end;
  FLastInsertOID := Result;
end;

function TFirebirdPersistStrategy.FillPrimaryKeyParam(PKParam: TDBXParameter;
  const Value: TValue): TValue;
begin
  try
    case FKeyType of
      ktString:
        begin
          PKParam.Value.SetString(Value.AsString);
          Result := PKParam.Value.GetString;
        end;
      ktInteger:
        begin
          PKParam.Value.AsInt64 := Value.AsInt64;
          Result := PKParam.Value.AsInt64;
        end;
    end;
  except
    on E: Exception do
      raise EdormException.Create('Error during fill primary key for query. ' +
        E.Message);
  end;
end;

function TFirebirdPersistStrategy.GetKeysGenerator: IdormKeysGenerator;
begin
  Result := FKeysGenerator;
end;

function TFirebirdPersistStrategy.GetKeyType: TdormKeyType;
begin
  Result := FKeyType;
end;

function TFirebirdPersistStrategy.GetLastInsertOID: TValue;
begin
  Result := FLastInsertOID;
end;

function TFirebirdPersistStrategy.GetLogger: IdormLogger;
begin
  Result := FLogger;
end;

procedure TFirebirdPersistStrategy.InitStrategy;
begin
  FLastInsertOID := TValue.Empty;
end;

function TFirebirdPersistStrategy.Insert(ARttiType: TRttiType; AObject: TObject;
  ATableName: string; AFieldsMapping: TArray<TdormFieldMapping>): TValue;
var
  field: TdormFieldMapping;
  sql_fields_names, sql_fields_values, SQL: ansistring;
  Query: TDBXCommand;
  I, pk_idx: Integer;
  v, pk_value: TValue;
begin
  sql_fields_names := '';
  for field in AFieldsMapping do
    sql_fields_names := sql_fields_names + ',"' + field.field + '"';

  System.Delete(sql_fields_names, 1, 1);

  sql_fields_values := '';
  for field in AFieldsMapping do
    sql_fields_values := sql_fields_values + ',?';
  System.Delete(sql_fields_values, 1, 1);

  SQL := Format('INSERT INTO %s (%S) VALUES (%S)',
    [ATableName, sql_fields_names, sql_fields_values]);
  GetLogger.Debug('PREPARING :' + SQL);
  Query := FB.Prepare(SQL);
  try
    I := 0;
    for field in AFieldsMapping do
    begin
      v := TdormUtils.GetField(AObject, field.name);

      if field.pk then
        pk_value := GenerateAndFillPrimaryKeyParam(Query.Parameters[I],
          ATableName)
      else
      begin
        SetDBXParameterValue(field.field_type, Query.Parameters[I], v);
      end;
      inc(I);
    end;
    GetLogger.Debug('EXECUTING PREPARED :' + SQL);
    FB.Execute(Query);
  finally
    Query.Free;
  end;
  pk_idx := GetPKMappingIndex(AFieldsMapping);
  TdormUtils.SetProperty(AObject, AFieldsMapping[pk_idx].name, pk_value);
  Result := pk_value;
end;

function TFirebirdPersistStrategy.InTransaction: Boolean;
begin
  Result := assigned(FCurTransaction);
end;

function TFirebirdPersistStrategy.IsNullKey(const Value: TValue): Boolean;
begin
  case FKeyType of
    ktInteger:
      Result := Value.AsInt64 = FNullKeyValue.AsInt64;
    ktString:
      Result := Value.AsString = FNullKeyValue.AsString;
  else
    raise EdormException.Create('Unknown key type');
  end;
end;

function TFirebirdPersistStrategy.GetNullKeyValue: TValue;
begin
  Result := FNullKeyValue;
end;

function TFirebirdPersistStrategy.List(ARttiType: TRttiType; ATableName: string;
  AFieldsMapping: TArray<TdormFieldMapping>;
  AdormSearchCriteria: IdormSearchCriteria): TdormCollection;
var
  SQL: string;
  cmd: TDBXCommand;
  reader: TDBXReader;
begin
  SQL := AdormSearchCriteria.GetSQL;
  GetLogger.Debug('PREPARING: ' + SQL);
  cmd := FB.Prepare(SQL);
  try
    GetLogger.Debug('EXECUTING PREPARED: ' + SQL);
    reader := cmd.ExecuteQuery;
    try
      Result := TdormCollection.Create;
      while reader.Next do
        Result.Add(CreateObjectFromDBXReader(ARttiType, reader,
          AFieldsMapping));
    finally
      reader.Free;
    end;
  finally
    cmd.Free;
  end;
end;

function TFirebirdPersistStrategy.Load(ARttiType: TRttiType; ATableName: string;
  AFieldsMapping: TArray<TdormFieldMapping>; const Value: TValue): TObject;
var
  pk_idx: Integer;
  pk_attribute_name, pk_field_name, SQL: string;
  cmd: TDBXCommand;
  reader: TDBXReader;
begin
  Result := nil;
  pk_idx := GetPKMappingIndex(AFieldsMapping);
  if pk_idx = -1 then
    raise Exception.Create('Invalid primary key for table ' + ATableName);
  pk_attribute_name := AFieldsMapping[pk_idx].name;
  pk_field_name := AFieldsMapping[pk_idx].field;
  SQL := 'SELECT ' + GetSelectFieldsList(AFieldsMapping, true) + ' FROM ' +
    ATableName + ' WHERE ' + pk_field_name + ' = ?';
  GetLogger.Debug('PREPARING: ' + SQL);
  cmd := FB.Prepare(SQL);
  try
    FillPrimaryKeyParam(cmd.Parameters[pk_idx], Value);
    GetLogger.Debug('EXECUTING PREPARED: ' + SQL);
    reader := cmd.ExecuteQuery();
    try
      if reader.Next then
        Result := CreateObjectFromDBXReader(ARttiType, reader, AFieldsMapping);
    finally
      reader.Free;
    end;
  finally
    cmd.Free;
  end;
end;

function TFirebirdPersistStrategy.LoadObjectFromDBXReader(ARttiType: TRttiType;
  AReader: TDBXReader; AFieldsMapping: TArray<TdormFieldMapping>;
  AObject: TObject): Boolean;
var
  obj: TObject;
  field: TdormFieldMapping;
  v: TValue;
begin
  Result := False;
  obj := AObject;
  for field in AFieldsMapping do
  begin
    if CompareText(field.field_type, 'string') = 0 then
      v := AReader.Value[AReader.GetOrdinal(field.field)].AsString
    else if CompareText(field.field_type, 'integer') = 0 then
      v := AReader.Value[AReader.GetOrdinal(field.field)].AsInt32
    else if CompareText(field.field_type, 'date') = 0 then
    begin
      v := AReader.Value[AReader.GetOrdinal(field.field)].AsDate

    end
    else
      raise Exception.Create('Unknown field type for ' + field.field);
    TdormUtils.SetField(obj, field.name, v);
  end;
  Result := true;
end;

function TFirebirdPersistStrategy.RawExecute(SQL: string): Int64;
begin
  GetLogger.Warning('RAW EXECUTE: ' + SQL);
  Result := FB.Execute(SQL);
end;

function TFirebirdPersistStrategy.CreateObjectFromDBXReader
  (ARttiType: TRttiType; AReader: TDBXReader;
  AFieldsMapping: TArray<TdormFieldMapping>): TObject;
var
  obj: TObject;
  // obj1: TStringBuilder;
  field: TdormFieldMapping;
  v: TValue;
  t: TTimeStamp;
  S: string;
  sourceStream: TStream;
  targetStream: TMemoryStream;
  v1: TValue;
begin
  Result := nil;
  try
    obj := TdormUtils.CreateObject(ARttiType);
    for field in AFieldsMapping do
    begin
      if CompareText(field.field_type, 'string') = 0 then
      begin
        v := AReader.Value[AReader.GetOrdinal(field.field)].AsString;
        S := field.field + ' as string';
      end
      else if CompareText(field.field_type, 'integer') = 0 then
      begin
        v := AReader.Value[AReader.GetOrdinal(field.field)].AsInt32;
        S := field.field + ' as integer';
      end
      else if CompareText(field.field_type, 'date') = 0 then
      begin
        t.Date := AReader.Value[AReader.GetOrdinal(field.field)].AsDate;
        t.Time := 0;
        v := TimeStampToDateTime(t);
        S := field.field + ' as date';
      end
      else if CompareText(field.field_type, 'blob') = 0 then
      begin
        targetStream := nil;
        sourceStream := AReader.Value[AReader.GetOrdinal(field.field)].AsStream;
        S := field.field + ' as blob';
        if assigned(sourceStream) then
        begin
          sourceStream.Position := 0;
          targetStream := TMemoryStream.Create;
          targetStream.CopyFrom(sourceStream, sourceStream.Size);
          targetStream.Position := 0;
        end;
        v := targetStream;
      end
      else if CompareText(field.field_type, 'decimal') = 0 then
      begin
        v := AReader.Value[AReader.GetOrdinal(field.field)].AsDouble;
        S := field.field + ' as decimal';
      end
      else if CompareText(field.field_type, 'boolean') = 0 then
      begin
        v := AReader.Value[AReader.GetOrdinal(field.field)].AsBoolean;
        S := field.field + ' as boolean';
      end
      else if CompareText(field.field_type, 'datetime') = 0 then
      begin
        v := AReader.Value[AReader.GetOrdinal(field.field)].AsDateTime;
        S := field.field + ' as datetime';
      end
      else
        raise Exception.Create('Unknown field type for ' + field.field);
      try
        TdormUtils.SetField(obj, field.name, v);
      except
        on E: Exception do
        begin

          raise EdormException.Create(E.Message + sLineBreak +
            '. Probably cannot write ' + ARttiType.ToString + '.' + S);
        end;
      end;
    end;
  except
    on E: Exception do
    begin

      raise;
    end;
  end;
  Result := obj;
end;

class procedure TFirebirdPersistStrategy.register;
begin
  //
end;

procedure TFirebirdPersistStrategy.Rollback;
begin
  if not assigned(FCurTransaction) then
    raise Exception.Create('Transaction is not active');
  FB.GetConnection.RollbackFreeAndNil(FCurTransaction);
end;

procedure TFirebirdPersistStrategy.SetDBXParameterValue(aFieldType: string;
  aParameter: TDBXParameter; aValue: TValue);
begin
  if CompareText(aFieldType, 'string') = 0 then
  begin
    aParameter.DataType := TDBXDataTypes.WideStringType;
  end
  else

    if CompareText(aFieldType, 'decimal') = 0 then
  begin
    aParameter.DataType := TDBXDataTypes.DoubleType;
  end
  else if CompareText(aFieldType, 'boolean') = 0 then
  begin
    aParameter.DataType := TDBXDataTypes.Int16Type;

  end
  else if CompareText(aFieldType, 'date') = 0 then
  begin
    aParameter.DataType := TDBXDataTypes.DateType;

  end
  else if CompareText(aFieldType, 'blob') = 0 then
  begin
    aParameter.DataType := TDBXDataTypes.BlobType;

  end;

  SetDBXValue(aFieldType, aParameter.Value, aValue);
end;

procedure TFirebirdPersistStrategy.SetDBXValue(aFieldType: string;
  aDBXValue: TDBXWritableValue; aValue: TValue);

var
  str: TBytesStream;
  sourceStream: TStream;
begin
  if CompareText(aFieldType, 'string') = 0 then
  begin
    aDBXValue.AsString := aValue.AsString;
  end
  else if CompareText(aFieldType, 'integer') = 0 then
  begin
    aDBXValue.AsBcd := IntegerToBcd(aValue.AsInt64);
  end
  else if CompareText(aFieldType, 'date') = 0 then
  begin
    aDBXValue.AsDate := DateTimeToTimeStamp(aValue.AsExtended).Date;
  end
  else if CompareText(aFieldType, 'datetime') = 0 then
  begin
    aDBXValue.AsDateTime := FloatToDateTime(aValue.AsExtended);
  end
  else if CompareText(aFieldType, 'blob') = 0 then
  begin
    sourceStream := TStream(aValue.AsObject);
    if sourceStream = nil then
      aDBXValue.SetNull
    else
    begin
      str := TBytesStream.Create;
      try
        sourceStream.Position := 0;
        str.CopyFrom(sourceStream, sourceStream.Size);
        str.Position := 0;
        aDBXValue.SetStream(str, true);
        aDBXValue.ValueType.ValueTypeFlags :=
          aDBXValue.ValueType.ValueTypeFlags or TDBXValueTypeFlags.ExtendedType;
      except
        str.Free;
        raise;
      end;
    end;
  end
  else if CompareText(aFieldType, 'decimal') = 0 then
  begin
    aDBXValue.AsDouble := aValue.AsExtended;
  end
  else if CompareText(aFieldType, 'boolean') = 0 then
  begin
    if aValue.AsBoolean then
      aDBXValue.AsInt16 := 1
    else
      aDBXValue.AsInt16 := 0;
  end
  else
    raise Exception.Create('Unsupported type ' + IntToStr(ord(aValue.Kind)));

end;

procedure TFirebirdPersistStrategy.SetLogger(ALogger: IdormLogger);
begin
  FLogger := ALogger;
end;

procedure TFirebirdPersistStrategy.StartTransaction;
begin
  if assigned(FCurTransaction) then
    raise Exception.Create('Transaction already active');
  FCurTransaction := FB.GetConnection.BeginTransaction
    (TDBXIsolations.ReadCommitted)
end;

{ TFirebirdTableSequence }

function TFirebirdTableSequence.NewIntegerKey(const Entity: string): UInt64;
begin
  Result := FPersistStrategy.ExecuteAndGetFirst('SELECT GEN_ID(SEQ_' + Entity +
    '_ID, 1) FROM RDB$DATABASE');
end;

function TFirebirdTableSequence.NewStringKey(const Entity: string): string;
begin
  raise EdormException.Create('String keys not supported');
end;

class procedure TFirebirdTableSequence.RegisterClass;
begin
  // do nothing
end;

// procedure TFirebirdTableSequence.SetFirebirdConnection
// (const Value: TDBXFactory);
// begin
// FFirebirdConnection := Value;
// end;

procedure TFirebirdTableSequence.SetPersistStrategy(const PersistentStrategy
  : IdormPersistStrategy);
begin
  FPersistStrategy := PersistentStrategy;
end;

initialization

TFirebirdPersistStrategy.register;
TFirebirdTableSequence.RegisterClass;

finalization

end.
