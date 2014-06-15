unit shelf;

interface

uses
  Jpeg, Classes, IniFiles, SysUtils, IdHTTP, IdSSLOpenSSL, IdCookieManager,
  IdCookie, IdURI, md5, StrUtils, superobject, Windows, DECCipher, Math,
  pngimage, Graphics;

type
  pPage = ^TPage;

  TPage = record
    Page, Nombre, Width, Height: integer;
    Chapter: string;
    DRM, DataPosition1, DataLength1, DataPosition2, DataLength2: integer;
  end;

  TBook = record
    ISBN_EBI: string;
    Title: string;
    AltName: string;
    Author: string;
    AltAuthor: string;
    Cover: string;
    Spine: string;
    EBI: string;
    Date: string;
    d1: string;
    d2: string;
    flag: string;
    Description: string;
    num: integer;
    SeriesName: string;
    NumOnSeries: integer;
    Pages: array of TPage;
  end;

  TShelf = class
  private
    fHTTP: TIdHTTP;
    fSSL: TIdSSLIOHandlerSocketOpenSSL;
    fCookie: TIdCookieManager;

    fUID: string;
    fEnvID: string;
    fCheck: string;
    fToken: string;
    fReaderID: string;
    fProcID: string;
    fResponse: array of TStringList;

    fBooksCount: integer;
    fBooks: array of TBook;

    function getUniquId(): string;
    function getEncodeEnvId(id: string): string;
    function getChecksum(s: string): string;

    procedure onCookie(ASender: TObject; ACookie: TIdCookieRFC2109;
      var VAccept: Boolean);

    function GetLoggedIn(): Boolean;
    function ParseResponse(reply: string): integer;
    function GetReaderID(): Boolean;
    procedure SyncBooksCount();
    procedure GetBooksList();
    procedure ParseBookList();
    function GetDevicesList(): Boolean;
    function DownloadDDD(): Boolean;
    procedure DecodeDRM(DRMenc: pAnsiChar; XORKey, AESKey: AnsiString;
      var DRMdec: string);
    procedure DecodePage(book: TFileStream; Page: pPage; DRM: string);

    function GetBook(Idx: integer): TBook;
  public
    constructor Create();
    destructor Destroy(); override;

    function LogIn(user, pass: string): Boolean;
    function Update(): integer;

    function DownloadBook(id: string): Boolean;

    procedure DecryptBook(drmFile, bookFile: string; KeyData: AnsiString);

    property LoggedIn: Boolean read GetLoggedIn;
    property BooksCount: integer read fBooksCount;
    property Books[Idx: integer]: TBook read GetBook;
  end;

implementation

resourcestring
  domainHTTPS = 'https://www.ebookjapan.jp/';
  authURL = 'ebj/user/br_authenticate.asp';
  loginURL = 'ebj/user/user_login_form.asp';
  version = '1.0.0.5';
  cid = 'browser';
  cid_md5 = 'b6ppyjqsm22vv633';
  BASE_PLATFORM_NAME = 'Shig';
  BASE_MODEL_NAME = 'Fenril';
  BASE_READER_NAME = 'ebiBrRe';
  BASE_READER_VER = '01020304';
  BASE_MAC_PARAM = 'f0f0f0f0f0f0';
  BASE_ENV_ID_VERSION = '1.00';

function str2Hexbin(str: string): string;
var
  i: integer;
begin
  result := '';
  for i := 1 to Length(str) do
    result := result + IntToHex(byte(AnsiChar(str[i])), 2);
end;

constructor TShelf.Create();
begin
  inherited Create();
  fHTTP := TIdHTTP.Create(nil);
  fSSL := TIdSSLIOHandlerSocketOpenSSL.Create(nil);
  fHTTP.IOHandler := fSSL;
  fHTTP.ReadTimeout := 5000;
  fHTTP.Request.UserAgent := 'Mozilla/5.0 (Windows NT 6.2; WOW64) ' +
    'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/35.0.1916.153 Safari/537.36';
  fCookie := TIdCookieManager.Create(nil);
  fCookie.OnNewCookie := onCookie;
  fHTTP.CookieManager := fCookie;
  fHTTP.AllowCookies := true;
  fToken := '';
  fBooksCount := 0;
end;

destructor TShelf.Destroy();
var
  i: integer;
begin
  if Length(fResponse) > 0 then
    for i := 0 to Length(fResponse) - 1 do
      fResponse[i].Free;
  SetLength(fResponse, 0);
  fHTTP.Free;
  fCookie.Free;
  fSSL.Free;
  inherited Destroy();
end;

procedure TShelf.onCookie(ASender: TObject; ACookie: TIdCookieRFC2109;
  var VAccept: Boolean);
begin
end;

function TShelf.ParseResponse(reply: string): integer;
var
  i, code: integer;
  list: TStringList;
begin
  if Length(fResponse) > 0 then
    for i := 0 to Length(fResponse) - 1 do
      fResponse[i].Free;
  SetLength(fResponse, 0);

  list := TStringList.Create;
  list.Text := reply;
  SetLength(fResponse, list.Count);
  for i := 0 to list.Count - 1 do
  begin
    fResponse[i] := TStringList.Create;
    fResponse[i].Delimiter := #9;
    fResponse[i].DelimitedText := list[i];
  end;
  list.Free;

  if (Length(fResponse) > 0) then
  begin
    code := StrToInt(fResponse[0][0]);
    case code of
      0002:
        fReaderID := fResponse[1][0];
    end;
    result := code;
  end
  else
    result := 0;
end;

function TShelf.LogIn(user, pass: string): Boolean;
var
  params: TStringList;
begin
  result := false;
  fUID := getUniquId;
  fEnvID := getEncodeEnvId(fUID);
  fCheck := getChecksum(cid_md5);
  params := TStringList.Create;
  params.Add('email=' + user);
  params.Add('passwd=' + pass);
  params.Add('login=1');
  params.Add('onclick_sub=onclick_sub');

  try
    fHTTP.Post(domainHTTPS + loginURL, params);
  except
    on e: EIDHttpProtocolException do
    begin
      if e.ErrorCode = 302 then
      begin
        if LoggedIn then
          result := true;
      end;
    end;
  end;
  params.Free;
end;

function TShelf.GetLoggedIn(): Boolean;
var
  tokenStart: integer;
begin
  result := false;
  try
    fHTTP.Get(domainHTTPS + authURL);
  except
    on e: EIDHttpProtocolException do
    begin
      if e.ErrorCode = 302 then
      begin
        tokenStart := PosEx('token=', fHTTP.response.Location);
        if tokenStart > 1 then
          fToken := Copy(fHTTP.response.Location, tokenStart + 6, 32);
        if Length(fToken) = 32 then
          result := true;
      end;
    end;
  end;
end;

function TShelf.Update(): integer;
begin
  result := 0;

  if (not GetReaderID()) then
    Exit;

  SyncBooksCount();
  result := fBooksCount;
end;

function TShelf.GetReaderID(): Boolean;
var
  params: TStringList;
  response: string;
begin
  result := false;
  params := TStringList.Create;

  params.Add('token=' + fToken);
  params.Add('cid=' + cid);
  params.Add('envid=' + fEnvID);
  params.Add('check=' + fCheck);
  params.Add('mode=login');
  params.Add('version=' + version);
  try
    response := fHTTP.Post(domainHTTPS + 'trunkif_asp/trunk_connect_token.asp',
      params);
    if ParseResponse(response) = 2 then
      result := true;
  finally
    params.Free;
  end;
end;

procedure TShelf.SyncBooksCount();
var
  params: TStringList;
  response: string;
begin
  params := TStringList.Create;

  params.Add('sessionid=' + fReaderID);
  params.Add('booknum=0');
  try
    response := fHTTP.Post(domainHTTPS +
        'trunkif_asp/synchronize_from_local.asp', params);
    if ParseResponse(response) = 1003 then
      GetBooksList();
  finally
    params.Free;
  end;
end;

procedure TShelf.GetBooksList();
var
  params: TStringList;
  response: string;
begin
  params := TStringList.Create;

  params.Add('folderid=-1');
  params.Add('sessionid=' + fReaderID);
  params.Add('sortid=0');
  params.Add('firstrownum=1');
  params.Add('lastrownum=200');
  params.Add('searchword=');
  try
    response := fHTTP.Post(domainHTTPS +
        'trunkif_asp/get_booklist_paging_search.asp', params);
    if ParseResponse(response) = 0 then
      ParseBookList();
  finally
    params.Free;
  end;
end;

procedure TShelf.ParseBookList();
var
  i: integer;
  booksRAW: TStringList;
begin
  fBooksCount := StrToInt(fResponse[3][0]);
  SetLength(fBooks, fBooksCount);
  for i := 0 to fBooksCount - 1 do
  begin
    booksRAW := fResponse[4 + i];
    fBooks[i].ISBN_EBI := booksRAW[0];
    fBooks[i].Title := booksRAW[1];
    fBooks[i].AltName := booksRAW[2];
    fBooks[i].Author := booksRAW[3];
    fBooks[i].AltAuthor := booksRAW[4];
    fBooks[i].Cover := booksRAW[5];
    fBooks[i].Spine := booksRAW[6];
    fBooks[i].EBI := booksRAW[7];
    fBooks[i].Date := booksRAW[8];
    fBooks[i].d1 := booksRAW[9];
    fBooks[i].d2 := booksRAW[10];
    fBooks[i].flag := booksRAW[11];
    fBooks[i].Description := booksRAW[12];
    { fBooks[i].num:=StrToInt(booksRAW[13]);
      fBooks[i].SeriesName:=booksRAW[14];
      fBooks[i].NumOnSeries:=StrToInt(booksRAW[15]); }
  end;
end;

function TShelf.DownloadBook(id: string): Boolean;
var
  params: TStringList;
  response: string;
begin
  result := false;
  if (not GetDevicesList()) then
    Exit;
  params := TStringList.Create;

  params.Clear;
  params.Add('sessionid=' + fReaderID);
  params.Add('bookid=' + id);
  params.Add('langid=XX');
  try
    response := fHTTP.Post(domainHTTPS + 'trunkif_asp/download_book.asp',
      params);
    if ParseResponse(response) = 0 then
    begin
      fProcID := fResponse[1][0];
      if DownloadDDD() then
        result := true;
    end;
  finally
    params.Free;
  end;
end;

function TShelf.GetDevicesList(): Boolean;
var
  params: TStringList;
  response: string;
begin
  result := false;
  params := TStringList.Create;

  params.Add('sessionid=' + fReaderID);
  try
    response := fHTTP.Post(domainHTTPS + 'trunkif_asp/get_devicelist.asp',
      params);
    if ParseResponse(response) = 0 then
      result := true;
  finally
    params.Free;
  end;
end;

type
  PWideStrArray = array of array of string;

function json_array_exploder(main, returnval: string): PWideStrArray;
var
  obj, id_obj, temp_obj: ISuperObject;
  i, Count, item: integer;
  array_result: PWideStrArray;
begin
  obj := SO(returnval);
  id_obj := obj[main];
  if (id_obj <> nil) then
  begin
    i := 0;
    Count := id_obj.AsArray.Length - 1;

    for item := 0 to Count do
    begin
      SetLength(array_result, i + 1, 3);
      temp_obj := obj[main + '[' + inttostr(i) + ']'];
      array_result[i][0] := temp_obj.AsArray.s[0];
      array_result[i][1] := temp_obj.AsArray.s[4];
      array_result[i][2] := temp_obj.AsArray.s[9];
      // showmessage(temp_obj.AsArray.S[0]);
      inc(i);
    end;
    result := array_result;
  end;
end;

function TShelf.DownloadDDD(): Boolean;
var
  params: TStringList;
  response: string;
  data: PWideStrArray;
begin
  result := false;
  params := TStringList.Create;

  params.Add('sessionid=' + fReaderID);
  params.Add('procid=' + fProcID);
  try
    response := fHTTP.Post(domainHTTPS + 'trunkif_asp/download_ddd.asp',
      params);
    data := json_array_exploder('Result', response);
    if (data[0][0] = '0') then
      result := true;
  finally
    params.Free;
  end;
end;

function TShelf.getUniquId(): string;
var
  res: string;
begin
  res := '4052765B5C005752646F' + FormatDateTime('YYYYMMDDHHNNSS123', Now())
    + '6E640E577D0200552964';
  result := str2Hexbin(res);
end;

function TShelf.getEncodeEnvId(id: string): string;
var
  uniqueID, pfName, modelName, readerName, readerVer, envIdVersion,
    macParam: string;
  block1, block2, block3, block4: string;
begin
  uniqueID := LowerCase(str2Hexbin(id));
  pfName := LowerCase(str2Hexbin(BASE_PLATFORM_NAME));
  modelName := Copy(LowerCase(str2Hexbin(BASE_MODEL_NAME))
      + '0000000000000000000000', 1, 22);
  readerName := LowerCase(str2Hexbin(BASE_READER_NAME));
  readerVer := LowerCase(str2Hexbin(BASE_READER_VER));
  envIdVersion := LowerCase(str2Hexbin(BASE_ENV_ID_VERSION));
  macParam := LowerCase(BASE_MAC_PARAM);

  block1 := Copy(uniqueID, 47, 34) + '0000' + pfName + '20';
  block2 := Copy(uniqueID, 1, 46) + '20';
  block3 := modelName + '0000000303500000' + envIdVersion + '20';
  block4 := readerName + '00' + readerVer + '00' + macParam + '20';
  result := block1 + block2 + block3 + block4;
end;

function TShelf.getChecksum(s: string): string;
var
  i: integer;
  str: string;
begin
  str := '';
  for i := 0 to 31 do
    str := str + inttostr(Round(Random() * 10));
  str := Copy(str + '00000000000000000000000000000000', 1, 32);
  s := str + s;
  result := LowerCase(str + MD5DigestToStr
      (MD5Buffer(AnsiString(s)[1], Length(s))));
end;

function TShelf.GetBook(Idx: integer): TBook;
begin
  result := fBooks[Idx];
end;

const
  Base64Filler: AnsiChar = '=';

type
  TAByte = array [0 .. MaxInt - 1] of byte;
  TPAByte = ^TAByte;

procedure Base64Decode(const InBuffer; InSize: DWord; var OutBuffer);
const
  cBase64Codec: array [0 .. 255] of byte = ($FF, $FF, $FF, $FF, $FF,
    { 005> } $FF, $FF, $FF, $FF, $FF, // 000..009
    $FF, $FF, $FF, $FF, $FF, { 015> } $FF, $FF, $FF, $FF, $FF, // 010..019
    $FF, $FF, $FF, $FF, $FF, { 025> } $FF, $FF, $FF, $FF, $FF, // 020..029
    $FF, $FF, $FF, $FF, $FF, { 035> } $FF, $FF, $FF, $FF, $FF, // 030..039
    $FF, $FF, $FF, $3E, $FF, { 045> } $FF, $FF, $3F, $34, $35, // 040..049
    $36, $37, $38, $39, $3A, { 055> } $3B, $3C, $3D, $FF, $FF, // 050..059
    $FF, $00, $FF, $FF, $FF, { 065> } $00, $01, $02, $03, $04, // 060..069
    $05, $06, $07, $08, $09, { 075> } $0A, $0B, $0C, $0D, $0E, // 070..079
    $0F, $10, $11, $12, $13, { 085> } $14, $15, $16, $17, $18, // 080..089
    $19, $FF, $FF, $FF, $FF, { 095> } $FF, $FF, $1A, $1B, $1C, // 090..099
    $1D, $1E, $1F, $20, $21, { 105> } $22, $23, $24, $25, $26, // 100..109
    $27, $28, $29, $2A, $2B, { 115> } $2C, $2D, $2E, $2F, $30, // 110..119
    $31, $32, $33, $FF, $FF, { 125> } $FF, $FF, $FF, $FF, $FF, // 120..129
    $FF, $FF, $FF, $FF, $FF, { 135> } $FF, $FF, $FF, $FF, $FF, // 130..139
    $FF, $FF, $FF, $FF, $FF, { 145> } $FF, $FF, $FF, $FF, $FF, // 140..149
    $FF, $FF, $FF, $FF, $FF, { 155> } $FF, $FF, $FF, $FF, $FF, // 150..159
    $FF, $FF, $FF, $FF, $FF, { 165> } $FF, $FF, $FF, $FF, $FF, // 160..169
    $FF, $FF, $FF, $FF, $FF, { 175> } $FF, $FF, $FF, $FF, $FF, // 170..179
    $FF, $FF, $FF, $FF, $FF, { 185> } $FF, $FF, $FF, $FF, $FF, // 180..189
    $FF, $FF, $FF, $FF, $FF, { 195> } $FF, $FF, $FF, $FF, $FF, // 190..199
    $FF, $FF, $FF, $FF, $FF, { 205> } $FF, $FF, $FF, $FF, $FF, // 200..209
    $FF, $FF, $FF, $FF, $FF, { 215> } $FF, $FF, $FF, $FF, $FF, // 210..219
    $FF, $FF, $FF, $FF, $FF, { 225> } $FF, $FF, $FF, $FF, $FF, // 220..229
    $FF, $FF, $FF, $FF, $FF, { 235> } $FF, $FF, $FF, $FF, $FF, // 230..239
    $FF, $FF, $FF, $FF, $FF, { 245> } $FF, $FF, $FF, $FF, $FF, // 240..249
    $FF, $FF, $FF, $FF, $FF, { 255> } $FF // 250..255
    );
var
  X, Y: integer;
  PIn, POut: TPAByte;
  Acc: DWord;
begin
  if (InSize > 0) and (InSize mod 4 = 0) then
  begin
    InSize := InSize shr 2;
    PIn := @InBuffer;
    POut := @OutBuffer;

    for X := 1 to InSize - 1 do
    begin
      Acc := 0;
      Y := -1;

      repeat
        inc(Y);
        Acc := Acc shl 6;
        Acc := Acc or cBase64Codec[PIn^[Y]];
      until Y = 3;

      POut^[0] := Acc shr 16;
      POut^[1] := byte(Acc shr 8);
      POut^[2] := byte(Acc);

      inc(Cardinal(PIn), 4);
      inc(Cardinal(POut), 3);
    end;
    Acc := 0;
    Y := -1;

    repeat
      inc(Y);
      Acc := Acc shl 6;

      if PIn^[Y] = byte(Base64Filler) then
      begin
        if Y = 3 then
        begin
          POut^[0] := Acc shr 16;
          POut^[1] := byte(Acc shr 8);
        end
        else
          POut^[0] := Acc shr 10;
        Exit;
      end;

      Acc := Acc or cBase64Codec[PIn^[Y]];
    until Y = 3;

    POut^[0] := Acc shr 16;
    POut^[1] := byte(Acc shr 8);
    POut^[2] := byte(Acc);
  end;
end;

procedure TShelf.DecryptBook(drmFile, bookFile: string; KeyData: AnsiString);
var
  stream: TFileStream;
  data, DRMenc, EBIX: AnsiString;
  obj, Page: ISuperObject;
  bookData, DRMdec: string;
  DRM, Pages: TSuperArray;
  i, PagesCount: integer;
  book: TBook;
begin
  stream := TFileStream.Create(drmFile, fmOpenRead);
  SetLength(data, stream.Size);
  stream.Read(data[1], stream.Size);
  stream.Free;

  obj := SO(data);
  EBIX := LowerCase(obj['Ebix'].AsString);
  Delete(EBIX, Length(EBIX) - 4, 5);
  bookData := obj['BookDataUrl'].AsString;
  DRMenc := obj['EncDrmData'].AsString;

  EBIX := MD5DigestToStr(MD5Buffer(EBIX[1], Length(EBIX)));
  DecodeDRM(@DRMenc[1], KeyData, EBIX, DRMdec);
  SetLength(DRMenc, 0);

  obj := SO(DRMdec);
  PagesCount := obj['cif'].AsObject.O['奥付'].AsInteger + 1;
  Writeln(PagesCount);
  DRM := obj['bif'].AsObject.O['DRM'].AsArray;
  for i := 0 to DRM.Length - 1 do
  begin
    Writeln(DRM.s[i]);
  end;

  SetLength(book.Pages, PagesCount);
  Pages := obj['pif'].AsArray;
  stream := TFileStream.Create(bookFile, fmOpenRead);
  if (not DirectoryExists(ExtractFilePath(bookFile) + 'pages')) then
    MkDir(ExtractFilePath(bookFile) + 'pages');
  for i := 0 to PagesCount - 1 do
  begin
    Page := Pages.O[i];
    book.Pages[i].Page := Page['Page'].AsInteger;
    book.Pages[i].Nombre := Page['Nombre'].AsInteger;
    book.Pages[i].Width := Page['Width'].AsInteger;
    book.Pages[i].Height := Page['Height'].AsInteger;
    book.Pages[i].Chapter := Page['Chapter'].AsString;
    book.Pages[i].DRM := Page['DRM'].AsInteger;
    book.Pages[i].DataPosition1 := Page['DataPosition1'].AsInteger;
    book.Pages[i].DataLength1 := Page['DataLength1'].AsInteger;
    book.Pages[i].DataPosition2 := Page['DataPosition2'].AsInteger;
    book.Pages[i].DataLength2 := Page['DataLength2'].AsInteger;

    DecodePage(stream, @book.Pages[i], LowerCase(DRM.s[book.Pages[i].DRM]));
  end;
  stream.Free;
end;

procedure TShelf.DecodeDRM(DRMenc: pAnsiChar; XORKey, AESKey: AnsiString;
  var DRMdec: string);
var
  drmSize, i, DRMdecSize: integer;
  key, IV: array [0 .. 15] of byte;
  AES: TCipher_Rijndael;
  DRMdecAnsi: AnsiString;
begin
  // дешифруем Base64-содержимое
  drmSize := Length(DRMenc) div 2;
  HexToBin(pAnsiChar(DRMenc), DRMenc[1], drmSize);
  for i := 0 to drmSize - 1 do
    DRMenc[i + 1] := AnsiChar(byte(DRMenc[i + 1]) xor ord(XORKey[i mod 64 + 1])
      );

  // пребразуем файл из Base64
  DRMdecSize := drmSize div 4 * 3;
  Base64Decode(DRMenc[1], drmSize, DRMenc[1]);

  // получаем ключ дешифрования
  HexToBin(pAnsiChar(AESKey), key, 16);
  FillChar(IV[0], 16, 0);
  SetLength(DRMdecAnsi, DRMdecSize);

  // дешифруем DRM
  AES := TCipher_Rijndael.Create();
  AES.Mode := cmECBx;
  AES.Init(key[0], 16, IV[0], 16);
  AES.Decode(DRMenc[1], DRMdecAnsi[1], (DRMdecSize div 16)*16);
  AES.Free;
  DRMdec := UTF8ToString(DRMdecAnsi);
  SetLength(DRMdecAnsi, 0);
end;

function numberTransform(chr: char): integer; inline;
begin
  result := ord(chr) - ord('a');
end;

procedure TShelf.DecodePage(book: TFileStream; Page: pPage; DRM: string);
var
  page_str: TFileStream;
  mem_stream: TMemoryStream;
  buf, pageBIN: array of byte;
  readedSize, pageSize: integer;
  divW, divH, gridW, gridH, cnt, i: integer;
  oW, oH, cW, cH, oX, oY, cX, cY: integer;
  pos: string;
  Jpeg: TJpegImage;
  png: TPngImage;
  tmp: TBitmap;
begin
  SetLength(buf, Page^.DataLength1 + Page^.DataLength2);

  book.Seek(Page^.DataPosition1, soBeginning);
  readedSize := book.Read(buf[0], Page^.DataLength1);

  book.Seek(Page^.DataPosition2, soBeginning);
  inc(readedSize, book.Read(buf[Page^.DataLength1], Page^.DataLength2));

  pageSize := readedSize div 4 * 3;
  SetLength(pageBIN, pageSize);
  Base64Decode(buf[0], readedSize, pageBIN[0]);
  SetLength(buf, 0);

  page_str:=TFileStream.Create(ExtractFilePath(book.FileName) + 'pages\page_' + inttostr
      (Page^.Page) + '.jpg', fmOpenWrite or fmCreate);
  page_str.Write(pageBIN[0], pageSize);
  page_str.Free;

  Exit;

  divW := StrToInt(DRM[1]) * 2;
  divH := (StrToInt(DRM[3]) - 1) * 2 + 1;
  gridW := Floor(Floor(Page^.Width / divW) / 8) * 8;
  gridH := Floor(Floor(Page^.Height / divH) / 8) * 8;
  pos := Copy(DRM, 5, Length(DRM) - 4);
  cnt := Length(pos) div 5;

  mem_stream := TMemoryStream.Create();
  mem_stream.Write(pageBIN[0], pageSize);
  mem_stream.Seek(0, soBeginning);
  SetLength(pageBIN, 0);
  Jpeg := TJpegImage.Create;
  Jpeg.LoadFromStream(mem_stream);
  mem_stream.Free;

  tmp := TBitmap.Create;
  tmp.Assign(Jpeg);

  if Jpeg.PixelFormat = jf8Bit then
    png := TPngImage.CreateBlank(COLOR_GRAYSCALE, 8, Page^.Width, Page^.Height)
  else
    png := TPngImage.CreateBlank(COLOR_RGB, 8, Page^.Width, Page^.Height);
  Jpeg.Free;
  for i := 0 to cnt - 1 do
  begin
    case pos[i * 5 + 3] of
      'a':
        begin
          oW := gridW;
          oH := gridH;
          cW := gridW;
          cH := gridH;
        end;
      'b':
        begin
          oW := gridW;
          oH := gridH * 2;
          cW := gridW;
          cH := gridH * 2;
        end;
      'c':
        begin
          oW := gridW * 2;
          oH := gridH;
          cW := gridW * 2;
          cH := gridH;
        end;
      'd':
        begin
          oW := gridW * 2;
          oH := gridH * 2;
          cW := gridW * 2;
          cH := gridH * 2;
        end;
    else
      begin
        oW := gridW;
        oH := gridH;
        cW := gridW;
        cH := gridH;
      end;
    end;
    oX := numberTransform(pos[i * 5 + 1]) * gridW;
    oY := numberTransform(pos[i * 5 + 2]) * gridH;
    cX := numberTransform(pos[i * 5 + 4]) * gridW;
    cY := numberTransform(pos[i * 5 + 5]) * gridH;
    png.Canvas.CopyRect(Rect(cX, cY, cX + cW, cY + cH), tmp.Canvas, Rect
        (oX, oY, oX + oW, oY + oH));
  end;

  oX := gridW * divW;
  oY := 0;
  oW := Page^.Width - oX;
  oH := Page^.Height;
  if (oW <> 0) then
    png.Canvas.CopyRect(Rect(oX, oY, oX + oW, oY + oH), tmp.Canvas, Rect
        (oX, oY, oX + oW, oY + oH));

  oX := 0;
  oY := gridH * divH;
  oW := gridW * divW;
  oH := Page^.Height - oY;
  if (oH <> 0) then
    png.Canvas.CopyRect(Rect(oX, oY, oX + oW, oY + oH), tmp.Canvas, Rect
        (oX, oY, oX + oW, oY + oH));

  tmp.Free;

  png.SaveToFile(ExtractFilePath(book.FileName) + 'pages\page_' + inttostr
      (Page^.Page) + '.png');
  png.Free;
end;

end.
