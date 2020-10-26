unit DW.Connectivity.Android;

{*******************************************************}
{                                                       }
{                      Kastri                           }
{                                                       }
{         Delphi Worlds Cross-Platform Library          }
{                                                       }
{    Copyright 2020 Dave Nottage under MIT license      }
{  which is located in the root folder of this library  }
{                                                       }
{*******************************************************}

{$I DW.GlobalDefines.inc}

interface

uses
  // Android
  Androidapi.JNI.Net, Androidapi.JNI.GraphicsContentViewText,
  // DW
  DW.MultiReceiver.Android, DW.Connectivity;

type
  TPlatformConnectivity = class;

  TConnectivityReceiver = class(TMultiReceiver)
  private
    FPlatformConnectivity: TPlatformConnectivity;
  protected
    procedure Receive(context: JContext; intent: JIntent); override;
    procedure ConfigureActions; override;
  public
    constructor Create(const APlatformConnectivity: TPlatformConnectivity);
  end;

  TPlatformConnectivity = class(TObject)
  private
    FConnectivity: TConnectivity;
    FReceiver: TConnectivityReceiver;
  private
    class function ConnectivityManager: JConnectivityManager; static;
  protected
    procedure ConnectivityChange(const AConnectivity: Boolean);
  public
    class function GetConnectedNetworkInfo: JNetworkInfo; static;
    class function IsConnectedToInternet: Boolean; static;
    class function IsWifiInternetConnection: Boolean; static;
  public
    constructor Create(const AConnectivity: TConnectivity);
    destructor Destroy; override;
  end;

implementation

uses
  DW.OSLog,
  System.SysUtils,
  // Android
  Androidapi.JNI.JavaTypes, Androidapi.Helpers, Androidapi.JNI.Os;

type
  TOpenConnectivity = class(TConnectivity);

{ TNetworkCallbackDelegate }

constructor TNetworkCallbackDelegate.Create(const APlatformConnectivity: TPlatformConnectivity);
begin
  inherited Create;
  FCallback := TJDWNetworkCallback.JavaClass.init(TAndroidHelper.Context, Self);
  FPlatformConnectivity := APlatformConnectivity;
end;

function TNetworkCallbackDelegate.IsConnectedToInternet: Boolean;
var
  LNetworks: TJavaObjectArray<JNetwork>;
  I: Integer;
begin
  Result := False;
  LNetworks := ConnectivityManager.getAllNetworks;
  try
    for I := 0 to LNetworks.Length - 1 do
    begin
      if GetConnectedNetworkInfoFromNetwork(LNetworks[I]) <> nil then
      begin
        Result := True;
        Break;
      end;
    end;
  finally
    LNetworks.Sync;
  end;
end;

function TNetworkCallbackDelegate.IndexOfNetwork(const ANetwork: JNetwork): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to Length(FConnectedNetworks) - 1 do
  begin
    if FConnectedNetworks[I] = ANetwork then
    begin
      Result := I;
      Break;
    end;
  end;
end;

class function TNetworkCallbackDelegate.ConnectivityManager: JConnectivityManager;
var
  LService: JObject;
begin
  if FConnectivityManager = nil then
  begin
    LService := TAndroidHelper.Context.getSystemService(TJContext.JavaClass.CONNECTIVITY_SERVICE);
    FConnectivityManager := TJConnectivityManager.Wrap(LService);
  end;
  Result := FConnectivityManager;
end;

procedure TNetworkCallbackDelegate.onAvailable(network: JNetwork);
begin
  TOSLog.d('TDWNetworkCallbackDelegate.onAvailable');
  FPlatformConnectivity.ConnectivityChange(IsConnectedToInternet);
end;

procedure TNetworkCallbackDelegate.onLost(network: JNetwork);
begin
  TOSLog.d('TDWNetworkCallbackDelegate.onLost');
  FPlatformConnectivity.ConnectivityChange(IsConnectedToInternet);
end;

procedure TNetworkCallbackDelegate.onUnavailable;
begin
  //
end;

// Based on: https://github.com/jamesmontemagno/ConnectivityPlugin/issues/56
class function TNetworkCallbackDelegate.GetConnectedNetworkInfo: JNetworkInfo;
var
  LAllNetworks: TJavaObjectArray<JNetwork>;
  LAllNetworkInfo: TJavaObjectArray<JNetworkInfo>;
  LInfo: JNetworkInfo;
  I: Integer;
begin
  Result := nil;
  if TJBuild_VERSION.JavaClass.SDK_INT >= 21 then
  begin
    LAllNetworks := ConnectivityManager.getAllNetworks;
    try
      for I := 0 to LAllNetworks.Length - 1 do
      begin
        LInfo := GetConnectedNetworkInfoFromNetwork(LAllNetworks[I]);
        if LInfo <> nil then
        begin
          Result := LInfo;
          Break;
        end;
      end;
    finally
      LAllNetworks.Sync;
    end;
  end
  else
  begin
    LAllNetworkInfo := ConnectivityManager.getAllNetworkInfo;
    try
      for I := 0 to LAllNetworkInfo.Length - 1 do
      begin
        LInfo := LAllNetworkInfo[I];
        if (LInfo <> nil) and LInfo.isAvailable and LInfo.isConnected then
        begin
          Result := LInfo;
          Break;
        end;
      end;
    finally
      LAllNetworkInfo.Sync;
    end;
  end;
end;

class function TNetworkCallbackDelegate.GetConnectedNetworkInfoFromNetwork(const ANetwork: JNetwork): JNetworkInfo;
var
  LCapabilities: JNetworkCapabilities;
  LInfo: JNetworkInfo;
begin
  LInfo := nil;
  LCapabilities := ConnectivityManager.getNetworkCapabilities(ANetwork);
  // Check if the network has internet capability
  if (LCapabilities <> nil) and LCapabilities.hasCapability(TJNetworkCapabilities.JavaClass.NET_CAPABILITY_INTERNET) then
  begin
    // ..and is Validated or SDK < 23
    if (TJBuild_VERSION.JavaClass.SDK_INT < 23) or LCapabilities.hasCapability(TJNetworkCapabilities.JavaClass.NET_CAPABILITY_VALIDATED) then
    begin
      LInfo := ConnectivityManager.getNetworkInfo(ANetwork);
      if (LInfo <> nil) and LInfo.isAvailable and LInfo.isConnected then
        Result := LInfo;
    end;
    // else
    //   TOSLog.d('Not validated');
  end;
end;

{ TConnectivityReceiver }

constructor TConnectivityReceiver.Create(const APlatformConnectivity: TPlatformConnectivity);
begin
  inherited Create;
  FPlatformConnectivity := APlatformConnectivity;
end;

procedure TConnectivityReceiver.ConfigureActions;
begin
  IntentFilter.addAction(TJConnectivityManager.JavaClass.CONNECTIVITY_ACTION);
end;

procedure TConnectivityReceiver.Receive(context: JContext; intent: JIntent);
begin
  if TJBuild_VERSION.JavaClass.SDK_INT < 21 then
  begin
    TOSLog.d('TConnectivityReceiver.Receive');
    FPlatformConnectivity.ConnectivityChange(TNetworkCallbackDelegate.GetConnectedNetworkInfo <> nil);
  end;
end;

{ TPlatformConnectivity }

constructor TPlatformConnectivity.Create(const AConnectivity: TConnectivity);
begin
  inherited Create;
  FConnectivity := AConnectivity;
  FIsConnectedToInternet := IsConnectedToInternet;
  if TJBuild_VERSION.JavaClass.SDK_INT >= 21 then
    FCallbackDelegate := TNetworkCallbackDelegate.Create(Self);
  FReceiver := TConnectivityReceiver.Create(Self);
  TOSLog.d('TPlatformConnectivity.Create > Connected: %s', [BoolToStr(FIsConnectedToInternet, True)]);
end;

destructor TPlatformConnectivity.Destroy;
begin
  // FCallbackDelegate.Free;
  FReceiver.Free;
  inherited;
end;

class function TPlatformConnectivity.IsConnectedToInternet: Boolean;
begin
  Result := TNetworkCallbackDelegate.GetConnectedNetworkInfo <> nil;
end;

class function TPlatformConnectivity.IsWifiInternetConnection: Boolean;
var
  LInfo: JNetworkInfo;
begin
  LInfo := TNetworkCallbackDelegate.GetConnectedNetworkInfo;
  Result := (LInfo <> nil) and (LInfo.getType = TJConnectivityManager.JavaClass.TYPE_WIFI);
end;

procedure TPlatformConnectivity.ConnectivityChange(const AIsConnected: Boolean);
begin
  TOSLog.d('TPlatformConnectivity.ConnectivityChange(%s)', [BoolToStr(AIsConnected, True)]);
  if FIsConnectedToInternet <> AIsConnected then
  begin
    TOSLog.d('> Changed from %s', [BoolToStr(FIsConnectedToInternet, True)]);
    FIsConnectedToInternet := AIsConnected;
    TOpenConnectivity(FConnectivity).DoConnectivityChange(FIsConnectedToInternet);
  end;
end;

end.
