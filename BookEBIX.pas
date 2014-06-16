unit BookEBIX;

interface

uses
  Classes, SysUtils, Windows, WinSock;

const
  EBIX_SIGN = 'HVQBOOK4.00';
  HVQ_SIGN = 'HVQ5 1.0';

type
  TEBIXHeader = record
    sign: array[0..15] of AnsiChar;
    headerSize: UInt32;
    EBI: array[0..31] of AnsiChar;
    date: array[0..31] of AnsiChar;
    sign2: array[0..15] of AnsiChar;
    CHAPoffset: UInt32;
    bookSize: UInt32;
    XINFoffset: UInt32;
    d1size: UInt32;
    d1: UInt32;
    d2: UInt32;
    d3: UInt32;
  end;

  TD1 = record
    d1: array[0..63] of AnsiChar;     // encryption key?
    d2: array[0..511] of AnsiChar;    // variable - session?
    d3: array[0..31] of AnsiChar;     // variable
    d4: array[0..39] of AnsiChar;
    d5: array[0..471] of AnsiChar;
  end;

  TXINFHeader = record
    sign: array[0..3] of AnsiChar;
    size: UInt32;
  end;

  TXINF = record
    Title: array[0..255] of WideChar;
    TitleAlt: array[0..255] of WideChar;
    Journal: array[0..255] of WideChar;
    JournalAlt: array[0..255] of WideChar;
    Author: array[0..255] of WideChar;
    AuthorAlt: array[0..255] of WideChar;
    Publisher: array[0..255] of WideChar;
    PublisherAlt: array[0..255] of WideChar;
    BookType: array[0..255] of WideChar;

    Year: array[0..15] of WideChar;
    Language: array[0..3]of WideChar;
    ISBN: array[0..23] of WideChar;
    d1: array[0..7] of WideChar;
    EBI: array[0..23] of WideChar;
    PagesCount: array[0..5] of WideChar;
    d2: array[0..1] of WideChar;

    SerieName: array[0..255] of WideChar;
    BookNo: array[0..31] of WideChar;
    d3: array[0..37] of WideChar;
  end;

  TDescriptionHeader = record
    size: UInt32;
    dataSize: UInt32;
  end;

  TIMGEHeader = packed record
    sign: array[0..3] of AnsiChar;
    d1: UInt32;   // always 0x1E
    size: UInt32;
    d2: UInt16;
    d3: uint32;
    d4: uint32;
    d5: uint32;
    Img2Offset: uint32;
  end;

  TCHAPHeader = record
    sign: array[0..3] of AnsiChar;
    HeaderSize: UInt32;
    MaxWidth: UInt32;
    MaxHeight: UInt32;
    d3: UInt32;
    d4: UInt32;
    d5: UInt32;
    d6: UInt32;
  end;

  TCHAP = record
    title: array[0..1] of WideChar;
    d1: UInt32;
    d2: UInt32;
    jumpOffset: UInt32;
  end;

  TPAGEHeader = record
    sign: array[0..3] of AnsiChar;
    size: UInt32;
  end;

  TPAGE = record
    pageNo: word;
    chapter: word;
    flags: word;
    JumpsCount: word;
    Width: word;
    Height: word;
    d4: UInt32;
    d5: UInt32;
    d6: UInt32;
  end;

  THVQHeader = packed record
    sign: array[0..15] of AnsiChar;
    DataSize: UInt32;
    HeaderSize: UInt32;
    Width: word;
    Height: word;
    d2: UInt32;
    d3: UInt32;
    d4: UInt32;
    ch_offset: array[0..15] of UInt32;
  end;

  THVQImage = class
  private
    fHeader: THVQHeader;

    fCH: array of array of byte;
  public
    constructor Create();
    destructor Destroy(); override;

    procedure ReadFromStream(stream: TStream);
  end;

  TBookEBIX = class
  private
    fHeader: TEBIXHeader;
    fD1: TD1;
    fXINFHeader: TXINFHeader;
    fXINF: TXINF;
    fDescriptionHeader: TDescriptionHeader;
    fDescription: pWideChar;
    fIMGEHeader: TIMGEHeader;
    fIMGE: array of byte;
    fCHAPHeader: TCHAPHeader;
    fChaptersCount: integer;
    fChaptersTitle: array of TCHAP;
    fPAGEHeader: TPAGEHeader;
    fPagesCount: integer;
    fPages: array of TPAGE;

    fImg1: THVQImage;
    fImg2: THVQImage;

  public
    constructor Create();
    destructor Destroy(); override;

    procedure LoadFromFile(FileName: string);
  end;

const
  FLAG_PAGE = $8000;

implementation

constructor TBookEBIX.Create();
begin
end;

destructor TBookEBIX.Destroy();
begin
  FreeMem(fDescription);
end;

procedure TBookEBIX.LoadFromFile(FileName: string);
var
  str: TFileStream;
  size, i: UInt32;
  img: THVQImage;
begin
  str:=TFileStream.Create(FileName, fmOpenRead);
  str.Read(fHeader, sizeof(TEBIXHeader));
  if fHeader.sign<>EBIX_SIGN then
    Exit;

  str.Read(fD1, sizeof(TD1));

  str.Read(fXINFHeader, sizeof(TXINFHeader));
  str.Read(fXINF, sizeof(TXINF));

  str.Read(fDescriptionHeader, sizeof(TDescriptionHeader));
  GetMem(fDescription, fDescriptionHeader.dataSize);
  str.Read(fDescription[0], fDescriptionHeader.dataSize);

  str.Read(fIMGEHeader, sizeof(TIMGEHeader));
  SetLength(fIMGE, fIMGEHeader.size-sizeof(TIMGEHeader));
  fImg1:=THVQImage.Create;
  fImg1.ReadFromStream(str);
  fImg2:=THVQImage.Create;
  fImg2.ReadFromStream(str);

  fImg1.Free;
  fImg2.Free;

  str.Read(fCHAPHeader, sizeof(TCHAPHeader));
  str.Read(size, sizeof(uint32));
  fChaptersCount:=(size-8) div sizeof(TCHAP);
  SetLength(fChaptersTitle, fChaptersCount);
  str.Read(fChaptersTitle[0], fChaptersCount*sizeof(TCHAP));
  str.Seek(8, soFromCurrent);

  str.Read(fPAGEHeader, sizeof(TPAGEHeader));
  fPagesCount:=(fPAGEHeader.size-sizeof(TPAGEHeader)) div sizeof(TPAGE);
  SetLength(fPages, fPagesCount);
  str.Read(fPages[0], fPagesCount*sizeof(TPAGE));

  Img:=THVQImage.Create;
  Img.ReadFromStream(str);

  if fHeader.sign<>EBIX_SIGN then
    Exit;
  str.Free;
end;

constructor THVQImage.Create();
begin
end;

destructor THVQImage.Destroy();
begin
  SetLength(fCH, 0, 0);
end;

type
  puint32 = ^uint32;

procedure SwapBytes(data: puint32; len: integer);
var
  i: integer;
begin
  for i:=0 to len-1 do
    puint32(uint32(data)+i*sizeof(uint32))^:=htonl(puint32(uint32(data)+i*sizeof(uint32))^);
end;

procedure THVQImage.ReadFromStream(stream: TStream);
var
  i, sz, start: uint32;
  str: TFileStream;
begin
  stream.Read(fHeader, sizeof(THVQHeader));
  SwapBytes(@fHeader.DataSize, 2);
  fHeader.Width:=htons(fHeader.Width);
  fHeader.Height:=htons(fHeader.Height);
  SwapBytes(@fHeader.d3, 18);
  if fHeader.sign<>HVQ_SIGN then
    Exit;

  SetLength(fCH, 16);
  start:=stream.Position;
  str:=TFileStream.Create('./img0', fmOpenWrite or fmCreate);
  for i:=0 to 15 do
  begin
    stream.Seek(start+fHeader.ch_offset[i], soBeginning);
    stream.Read(sz, 4);
    sz:=htonl(sz);
    SetLength(fCH[i], sz);
    stream.Read(fCH[i][0], sz);

    str.Write(fCH[i][0], sz);
  end;
  str.Free;
  //stream.Seek(fHeader.DataSize, soCurrent);
end;

end.
