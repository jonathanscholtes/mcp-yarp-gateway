using Yarp.ReverseProxy.Configuration;
using Yarp.ReverseProxy.Model;
using Yarp.ReverseProxy.SessionAffinity;

/// <summary>
/// Stateless YARP session-affinity policy for MCP sessions.
///
/// Encodes the destination ID directly into the <c>Mcp-Session-Id</c> response header
/// so that every subsequent client request carries enough information to route itself
/// back to the correct backend pod — no shared state between YARP replicas required.
///
/// Header format:  <c>{DestinationId}.{OriginalSessionId}</c>
///   e.g.  <c>D2.ccca73a7-1350-4bb3-b8f7-9a042d44c001</c>
///
/// Flow:
///   1. First request (no Mcp-Session-Id) → AffinityKeyNotSet → LB picks a pod.
///   2. Backend responds with <c>mcp-session-id: &lt;uuid&gt;</c>.
///      AffinitizeResponse rewrites the header to <c>D2.&lt;uuid&gt;</c>.
///   3. Client echoes the full encoded value on subsequent requests.
///      FindAffinitizedDestinations parses the prefix, restores the original
///      header, and routes directly to the correct destination.
///
/// Benefits:
///   - Fully stateless — works with any number of YARP replicas.
///   - No ConcurrentDictionary, no Redis, no shared volume.
///   - Pod restarts / rolling updates are transparent; the client carries the routing info.
/// </summary>
internal sealed class McpSessionAffinityPolicy : ISessionAffinityPolicy
{
    private const string McpSessionHeader = "Mcp-Session-Id";
    private const char Separator = '.';
    private readonly ILogger<McpSessionAffinityPolicy> _logger;

    public McpSessionAffinityPolicy(ILogger<McpSessionAffinityPolicy> logger)
    {
        _logger = logger;
    }

    /// <summary>Policy name referenced in <c>appsettings.json</c>.</summary>
    public string Name => "McpSessionId";

    /// <summary>
    /// Parse the encoded session header to extract the destination ID and restore
    /// the original session value before the request reaches the backend.
    /// </summary>
    public AffinityResult FindAffinitizedDestinations(
        HttpContext context,
        ClusterState cluster,
        SessionAffinityConfig config,
        IReadOnlyList<DestinationState> destinations)
    {
        var rawHeader = context.Request.Headers[McpSessionHeader].FirstOrDefault();

        if (string.IsNullOrEmpty(rawHeader))
        {
            _logger.LogInformation("[MCP-Affinity] No Mcp-Session-Id on request — letting LB decide.");
            return new AffinityResult(null, AffinityStatus.AffinityKeyNotSet);
        }

        // Encoded format: {DestinationId}.{OriginalSessionId}
        var separatorIndex = rawHeader.IndexOf(Separator);
        if (separatorIndex <= 0 || separatorIndex >= rawHeader.Length - 1)
        {
            // Header present but not in the encoded format — likely a raw session ID
            // from a client that connected before the encoding was deployed, or a
            // non-standard caller. Let the LB pick a destination.
            _logger.LogWarning("[MCP-Affinity] Session header '{Header}' has no destination prefix. Redistributing.", rawHeader);
            return new AffinityResult(null, AffinityStatus.AffinityKeyNotSet);
        }

        var destId = rawHeader[..separatorIndex];
        var originalSessionId = rawHeader[(separatorIndex + 1)..];

        // Restore the original session ID so the backend sees the value it expects.
        context.Request.Headers[McpSessionHeader] = originalSessionId;

        var match = destinations.FirstOrDefault(d =>
            string.Equals(d.DestinationId, destId, StringComparison.OrdinalIgnoreCase));

        if (match is null)
        {
            _logger.LogWarning("[MCP-Affinity] Destination '{Dest}' (from session header) not found among available destinations. Redistributing.", destId);
            return new AffinityResult(null, AffinityStatus.DestinationNotFound);
        }

        _logger.LogInformation("[MCP-Affinity] Routed session {SessionId} → {Dest} (stateless affinity hit)", originalSessionId, destId);
        return new AffinityResult([match], AffinityStatus.OK);
    }

    /// <summary>
    /// Rewrite the backend's <c>mcp-session-id</c> response header to include the
    /// destination ID prefix so the client carries the routing information.
    /// </summary>
    public void AffinitizeResponse(
        HttpContext context,
        ClusterState cluster,
        SessionAffinityConfig config,
        DestinationState destination)
    {
        var responseSessionId = context.Response.Headers[McpSessionHeader].FirstOrDefault();

        if (string.IsNullOrEmpty(responseSessionId))
        {
            _logger.LogDebug("[MCP-Affinity] AffinitizeResponse — no session header on response from {Dest}.", destination.DestinationId);
            return;
        }

        // Only encode if not already prefixed (idempotent).
        if (responseSessionId.StartsWith(destination.DestinationId + Separator, StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogDebug("[MCP-Affinity] Response session header already prefixed: {Header}", responseSessionId);
            return;
        }

        var encoded = $"{destination.DestinationId}{Separator}{responseSessionId}";
        context.Response.Headers[McpSessionHeader] = encoded;

        _logger.LogInformation("[MCP-Affinity] Encoded session header: {Encoded} (dest={Dest})", encoded, destination.DestinationId);
    }
}
