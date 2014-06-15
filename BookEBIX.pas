unit BookEBIX;

interface

uses
  Classes, SysUtils;

const
  EBIX_SIGN = 'HVQBOOK4.00';

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
    key1: array[0..63] of AnsiChar;
    key2: array[0..511] of AnsiChar;
    key3: array[0..31] of AnsiChar;
    key4: array[0..39] of AnsiChar;
    key5: array[0..471] of AnsiChar;
  end;

  TXINFHeader = record
    sign: array[0..3] of AnsiChar;
    size: UInt32;
  end;

  TXINFBlock = record
    data: array[0..511] of AnsiChar;
  end;

  TXINFD1 = record
    d1: array[0..31] of AnsiChar;
    JPN: array[0..3]of WideChar;
    d2: array[0..23] of WideChar;
    d3: array[0..15] of AnsiChar;
    EBI: array[0..23] of WideChar;
    d4: array[0..15] of AnsiChar;
  end;

  TXINF = record
    blocks1_9: array[0..8] of TXINFBlock;
    d1: TXINFD1;
    block10: TXINFBlock;
    d2: array[0..139] of AnsiChar;
  end;

  T4Header = record
    size: UInt32;
    dataSize: UInt32;
  end;

  TIMGEHeader = record
    sign: array[0..3] of AnsiChar;
    d1: UInt32;
    size: UInt32;
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
    //d3: UInt32;
    d4: UInt32;
    d5: UInt32;
    d6: UInt32;
  end;

  TBookEBIX = class
  private
    fHeader: TEBIXHeader;
    fD1: TD1;
    fXINFHeader: TXINFHeader;
    fXINF: TXINF;
    f4Size: UInt32;
    f4Header: T4Header;
    f4Data: array of byte;
    fIMGEHeader: TIMGEHeader;
    fIMGE: array of byte;
    fCHAPHeader: TCHAPHeader;
    fChaptersCount: integer;
    fChaptersTitle: array of TCHAP;
    fPAGEHeader: TPAGEHeader;
    fPagesCount: integer;
    fPages: array of TPAGE;

  public
    procedure LoadFromFile(FileName: string);
  end;

const
  FLAG_PAGE = $8000;

implementation

procedure TBookEBIX.LoadFromFile(FileName: string);
var
  str: TFileStream;
  size: UInt32;
begin
  str:=TFileStream.Create(FileName, fmOpenRead);
  str.Read(fHeader, sizeof(TEBIXHeader));
  {if fHeader.sign<>EBIX_SIGN then
    Exit; }

  str.Read(fD1, sizeof(TD1));

  str.Read(fXINFHeader, sizeof(TXINFHeader));
  str.Read(fXINF, sizeof(TXINF));

  str.Read(f4Header, sizeof(T4Header));
  SetLength(f4Data, f4Header.dataSize);
  str.Read(f4Data[0], f4Header.dataSize);

  str.Read(fIMGEHeader, sizeof(TIMGEHeader));
  SetLength(fIMGE, fIMGEHeader.size-sizeof(TIMGEHeader));
  str.Read(fIMGE[0], fIMGEHeader.size-sizeof(TIMGEHeader));

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

  if fHeader.sign<>EBIX_SIGN then
    Exit;
  str.Free;
end;

end.
