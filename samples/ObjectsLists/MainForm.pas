unit MainForm;

interface

uses
  dorm, dorm.Collections, dorm.Commons,
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.Layouts, FMX.ListBox,
  BusinessObjects, Data.Bind.EngExt, FMX.Bind.DBEngExt, Data.Bind.Components,
  System.Rtti, System.Bindings.Outputs, System.Bindings.Helper,
  FMX.Edit, FMX.Objects,
  FMX.Bind.Editors; // Used to bind ListBox1 (Editor)

type
  TForm11 = class(TForm)
    ListBox1: TListBox;
    BindingsList1: TBindingsList;
    BindScopePeople: TBindScope;
    BindList1: TBindList;
    Button1: TButton;
    Button2: TButton;
    Edit1: TEdit;
    BindScopePerson: TBindScope;
    BindExprItems1: TBindExprItems;
    Edit2: TEdit;
    SpinBox1: TSpinBox;
    BindExprItems2: TBindExprItems;
    BindExprItems3: TBindExprItems;
    Rectangle1: TRectangle;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    CheckBox1: TCheckBox;
    BindExpression1: TBindExpression;
    Button3: TButton;
    Edit3: TEdit;
    Button4: TButton;
    Label4: TLabel;
    Button5: TButton;
    StyleBook1: TStyleBook;
    ScaledLayout1: TScaledLayout;
    BindScopeLaptops: TBindScope;
    ListBox2: TListBox;
    BindList2: TBindList;
    Label5: TLabel;
    Label6: TLabel;
    Button6: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Edit1Exit(Sender: TObject);
    procedure SpinBox1Change(Sender: TObject);
    procedure ListBox1Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure Button6Click(Sender: TObject);
  private
    People: TdormCollection;
    Session: TSession;
    procedure InitializeData;
  public
    { Public declarations }
  end;

var
  Form11: TForm11;

implementation

uses
  Generics.Collections;

{$R *.fmx}

procedure TForm11.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Session.Free;
end;

procedure TForm11.FormCreate(Sender: TObject);
begin
  Session := TSession.CreateConfigured(TStreamReader.Create('dorm.conf'),
    deDevelopment);
{$REGION 'Insert some data'}
//   InitializeData;
{$ENDREGION}
  People := Session.ListAll<TPerson>;
  BindScopePeople.DataObject := People;
  BindScopePeople.Active := True;
  BindList1.FillList;
end;

procedure TForm11.InitializeData;
var
  p: TPerson;
begin
  People := NewList;
  Session.DeleteAll(TPerson);
  p := TPerson.Create('Daniele', 'Teti', 32);
  p.Laptops := NewList;
  p.Laptops.Add(TLaptop.Create('DELL LATITUDE', 2048, 2));
  p.Laptops.Add(TLaptop.Create('COMPAQ PRESARIO', 2048, 4));
  People.Add(p);

  p := TPerson.Create('Scott', 'Summers', 40);
  p.Laptops := NewList;
  p.Laptops.Add(TLaptop.Create('DELL A707', 4096, 8));
  People.Add(p);

  p := TPerson.Create('Bruce', 'Banner', 50);
  p.Laptops := NewList;
  p.Laptops.Add(TLaptop.Create('DELL A101', 1024, 1));
  People.Add(p);

  People.Add(TPerson.Create('Sue', 'Storm', 35));
  People.Add(TPerson.Create('Peter', 'Parker', 17));
  Session.InsertCollection(People);
  People.Free;
end;

procedure TForm11.Button1Click(Sender: TObject);
begin
  BindList1.FillList;
end;

procedure TForm11.Button2Click(Sender: TObject);
begin
  BindScopePerson.Active := False;
  BindScopePerson.DataObject := TPerson.Create('...', '...', 20);
  People.Add(BindScopePerson.DataObject as TPerson);
  BindList1.FillList;
  ListBox1.ItemIndex := ListBox1.Items.Count - 1;
end;

procedure TForm11.Button3Click(Sender: TObject);
begin
  Session.Persist(BindScopePerson.DataObject);
  BindList1.FillList;
end;

procedure TForm11.Button4Click(Sender: TObject);
var
  Criteria: TdormCriteria;
begin
  BindScopePeople.Active := False;
  FreeAndNil(People);
  if Edit3.Text = EmptyStr then
    People := Session.ListAll<TPerson>
  else
  begin
    Criteria := TdormCriteria.NewCriteria('FirstName',
      TdormCompareOperator.Equal, Edit3.Text);
    People := Session.List<TPerson>(Criteria);
  end;
  BindScopePeople.DataObject := People;
  BindScopePeople.Active := True;
  BindList1.FillList;
end;

procedure TForm11.Button5Click(Sender: TObject);
begin
  BindScopePerson.Active := False;
  Session.Delete(People.Extract(BindScopePerson.DataObject));
  BindScopePerson.DataObject := nil;
  BindScopePerson.Active := True;
  BindList1.FillList;
end;

procedure TForm11.Button6Click(Sender: TObject);
var
  res: TArray<String>;
  l: TLaptop;
begin
  SetLength(res, 3);
  if InputQuery('New Laptop', ['Model', 'RAM [MB]', 'Cores'], res) then
  begin
    l := TLaptop.Create(res[0], strtoint(res[1]), strtoint(res[2]));
    TPerson(People[ListBox1.ItemIndex]).Laptops.Add(l);
    l.Owner := People[ListBox1.ItemIndex] as TPerson;
    Session.Persist(l);
    BindList2.FillList;
  end;
end;

procedure TForm11.Edit1Exit(Sender: TObject);
begin
  TBindings.Notify(Sender, 'Text');
end;

procedure TForm11.FormDestroy(Sender: TObject);
begin
  People.Free;
end;

procedure TForm11.ListBox1Click(Sender: TObject);
begin
  if ListBox1.ItemIndex > -1 then
  begin
    BindScopePerson.Active := False;
    BindScopeLaptops.Active := False;
    Session.LoadRelations(People[ListBox1.ItemIndex]);
    BindScopePerson.DataObject := People[ListBox1.ItemIndex];
    BindScopeLaptops.DataObject := TPerson(People[ListBox1.ItemIndex]).Laptops;
    BindScopePerson.Active := True;
    BindScopeLaptops.Active := True;
    BindList2.FillList;
  end;
end;

procedure TForm11.SpinBox1Change(Sender: TObject);
begin
  TBindings.Notify(Sender, 'Value');
end;

end.
