using System.Collections.Concurrent;
using Yarp.ReverseProxy.Configuration;
using Yarp.ReverseProxy.Model;
using Yarp.ReverseProxy.SessionAffinity;

/// <summary>
/// Custom YARP session affinity policy that pins MCP sessions to a specific backend pod
/// using an in-memory map of <c>Mcp-Session-Id → DestinationId</c>.
///
/// How it works:
///   1. First request (no Mcp-Session-Id): no affinity key → load balancer picks a pod normally.
///   2. The MCP server responds with Mcp-Session-Id on the response.
///      AffinitizeResponse captures this mapping (session ID → destination that handled it).
///   3. All subsequent requests carrying that Mcp-Session-Id are routed directly to the
///      same pod via the in-memory map — no hashing, no guessing.
///
/// Constraints:
///   - Requires a single YARP replica (in-process state). With multiple YARP replicas,
///     requests can land on a pod that doesn't have the mapping. Use Redis or configure
///     ASP.NET Data Protection with a shared key ring if HA on the proxy tier is required.
///   - Pod restarts clear all mappings; MCP clients must reinitialise their sessions,
///     which is expected behaviour per the MCP spec.
/// </summary>
internal sealed class McpSessionAffinityPolicy : ISessionAffinityPolicy
{
    private const string McpSessionHeader = "Mcp-Session-Id";

    // sessionId → destinationId (e.g. "d2")
    private readonly ConcurrentDictionary<string, string> _sessionMap = new(StringComparer.Ordinal);
    private readonly ILogger<McpSessionAffinityPolicy> _logger;

    public McpSessionAffinityPolicy(ILogger<McpSessionAffinityPolicy> logger)
    {
        _logger = logger;
    }

    /// <summary>Policy name referenced in <c>appsettings.json</c>.</summary>
    public string Name => "McpSessionId";

    /// <summary>
    /// Look up the destination for an existing session, or signal "no affinity yet"
    /// so the load balancer can pick freely on the first request.
    /// </summary>
    public AffinityResult FindAffinitizedDestinations(
        HttpContext context,
        ClusterState cluster,
        SessionAffinityConfig config,
        IReadOnlyList<DestinationState> destinations)
    {
        var sessionId = context.Request.Headers[McpSessionHeader].FirstOrDefault();

        if (string.IsNullOrEmpty(sessionId))
        {
            _logger.LogInformation("[MCP-Affinity] No Mcp-Session-Id on request — letting LB decide. Map size: {Count}", _sessionMap.Count);
            return new AffinityResult(null, AffinityStatus.AffinityKeyNotSet);
        }

        if (!_sessionMap.TryGetValue(sessionId, out var destinationId))
        {
            _logger.LogWarning("[MCP-Affinity] Session {SessionId} NOT in map (map size: {Count}). Redistributing.", sessionId, _sessionMap.Count);
            return new AffinityResult(null, AffinityStatus.AffinityKeyNotSet);
        }

        var match = destinations.FirstOrDefault(d => d.DestinationId == destinationId);
        if (match is null)
        {
            _logger.LogWarning("[MCP-Affinity] Session {SessionId} pinned to {Dest} but destination is gone. Removing.", sessionId, destinationId);
            _sessionMap.TryRemove(sessionId, out _);
            return new AffinityResult(null, AffinityStatus.DestinationNotFound);
        }

        _logger.LogInformation("[MCP-Affinity] Session {SessionId} → {Dest} (affinity hit)", sessionId, destinationId);
        return new AffinityResult([match], AffinityStatus.OK);
    }

    /// <summary>
    /// Called after the upstream responds to a request. If the response carries a
    /// new Mcp-Session-Id we record which destination handled it so future requests
    /// can be pinned correctly.
    /// </summary>
    public void AffinitizeResponse(
        HttpContext context,
        ClusterState cluster,
        SessionAffinityConfig config,
        DestinationState destination)
    {
        // The MCP server sets Mcp-Session-Id on the *response* for the first request.
        var sessionId = context.Response.Headers[McpSessionHeader].FirstOrDefault();

        _logger.LogInformation("[MCP-Affinity] AffinitizeResponse called. Dest={Dest}, ResponseSessionId={SessionId}, ResponseHeaders=[{Headers}]",
            destination.DestinationId,
            sessionId ?? "(null)",
            string.Join(", ", context.Response.Headers.Select(h => h.Key)));

        if (!string.IsNullOrEmpty(sessionId))
        {
            var added = _sessionMap.TryAdd(sessionId, destination.DestinationId);
            _logger.LogInformation("[MCP-Affinity] Mapped session {SessionId} → {Dest} (new={Added}, map size={Count})",
                sessionId, destination.DestinationId, added, _sessionMap.Count);
        }
    }
}
