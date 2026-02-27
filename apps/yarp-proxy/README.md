# MCP YARP Proxy

Minimal ASP.NET Core + YARP reverse proxy for MCP traffic with API-key authentication.

## Behavior
- Proxies requests from `/mcp/{**catch-all}` to the upstream MCP server.
- Validates API key on all `/mcp` requests.
- Does not inspect request bodies.
- Does not rewrite response bodies.
- Uses a longer upstream timeout (default: 10 minutes) to avoid premature timeout failures.

## Configuration
Set with `appsettings.json` and/or environment variables:

- `Proxy:ApiKeyHeader` (`PROXY__APIKEYHEADER`)
- `Proxy:ApiKey` (`PROXY__APIKEY`)
- `Proxy:UpstreamTimeoutMinutes` (`PROXY__UPSTREAMTIMEOUTMINUTES`)
- `ReverseProxy:Clusters:mcp-cluster:Destinations:d1:Address`
  (`REVERSEPROXY__CLUSTERS__MCP-CLUSTER__DESTINATIONS__D1__ADDRESS`)

Optional affinity:
- `ReverseProxy:Clusters:mcp-cluster:SessionAffinity:Enabled`

## Run
From the `Proxy` folder:

```powershell
dotnet restore
dotnet run
```

Default local endpoint:
- `http://localhost:5190` (or `ASPNETCORE_URLS` if set)

## Notebook integration
Point notebook `MCP_SERVER_URL` to this proxy endpoint (for example `http://localhost:5190/mcp`).

Add the proxy API key as MCP tool header in the notebook config (same header/value as proxy expects).

## Local development upstream
`appsettings.Development.json` overrides the upstream to `http://localhost:3000/`.

Start the MongoDB MCP server locally before running the proxy:

```powershell
$env:MDB_MCP_CONNECTION_STRING="<your-documentdb-connection-string>"
npx -y mongodb-mcp-server@latest --transport http --httpHost 0.0.0.0 --httpPort 3000 --readOnly
```

Then run the proxy as normal — it will forward `/mcp/*` to the local MCP server on port 3000.

## AKS upstream
In AKS, `appsettings.json` points to the in-cluster service:

```
http://mongodb-mcp-server.tools.svc.cluster.local:3000/
```

Deploy the MongoDB MCP server with its own Helm chart at `k8s/helm/mongodb-mcp-server`.
