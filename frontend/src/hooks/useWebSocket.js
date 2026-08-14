import { useState, useEffect, useRef, useCallback } from 'react';
import { getBackendUrl, WS_ENDPOINT } from '../utils/constants';
import { archiveReport as archiveReportApi } from '../services/api';

export const useWebSocket = () => {
  const [isConnected, setIsConnected] = useState(false);
  const [reportLines, setReportLines] = useState([]);
  const [isStreaming, setIsStreaming] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false);
  const [error, setError] = useState(null);
  const [reportId, setReportId] = useState(null);
  const [isArchived, setIsArchived] = useState(false);
  const [isArchiving, setIsArchiving] = useState(false);

  const wsRef = useRef(null);
  const reconnectCountRef = useRef(0);
  const MAX_RECONNECT = 5;

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    try {
      const wsUrl = `${getBackendUrl()}${WS_ENDPOINT}`;
      const ws = new WebSocket(wsUrl);

      ws.onopen = () => {
        setIsConnected(true);
        reconnectCountRef.current = 0;
        setError(null);
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);

          switch (data.type) {
            case 'chunk':
              setReportLines((prev) => [...prev, data.content]);
              setIsStreaming(true);
              break;
            case 'done': {
              // { type: "done", report: "...", report_id: 123 }
              if (data.report_id != null) {
                setReportId(data.report_id);
              }
              if (typeof data.report === 'string' && data.report) {
                setReportLines([data.report]);
              }
              setIsStreaming(false);
              setIsProcessing(false);
              setIsArchived(false);
              break;
            }
            case 'error':
              setError(data.message || 'Unknown error occurred');
              setIsStreaming(false);
              setIsProcessing(false);
              break;
            default:
              console.warn('Unknown message type:', data.type);
          }
        } catch (err) {
          console.error('Failed to parse WebSocket message', err);
        }
      };

      ws.onclose = () => {
        setIsConnected(false);
        wsRef.current = null;

        if (reconnectCountRef.current < MAX_RECONNECT) {
          reconnectCountRef.current += 1;
          setTimeout(connect, 3000);
        } else {
          setError('Failed to connect to the server after multiple attempts.');
        }
      };

      ws.onerror = (err) => {
        console.error('WebSocket error:', err);
      };

      wsRef.current = ws;
    } catch (err) {
      console.error('Failed to establish WebSocket connection:', err);
    }
  }, []);

  useEffect(() => {
    connect();
    return () => {
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, [connect]);

  const sendDiagnosis = useCallback((logText, serverId) => {
    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      setReportLines([]);
      setReportId(null);
      setIsArchived(false);
      setIsProcessing(true);
      setError(null);

      wsRef.current.send(
        JSON.stringify({
          action: 'diagnose',
          log_text: logText,
          server_id: serverId,
        })
      );
    } else {
      setError('WebSocket is not connected');
    }
  }, []);

  const archiveReport = useCallback(async () => {
    if (reportId == null) {
      throw new Error('No report_id available to archive');
    }
    if (isArchived) {
      return { status: 'ok', message: 'Already archived' };
    }
    setIsArchiving(true);
    try {
      const result = await archiveReportApi(reportId);
      setIsArchived(true);
      return result;
    } finally {
      setIsArchiving(false);
    }
  }, [reportId, isArchived]);

  const resetReport = useCallback(() => {
    setReportLines([]);
    setReportId(null);
    setIsArchived(false);
    setIsStreaming(false);
    setIsProcessing(false);
    setError(null);
  }, []);

  return {
    isConnected,
    reportLines,
    isStreaming,
    isProcessing,
    error,
    reportId,
    isArchived,
    isArchiving,
    archiveReport,
    sendDiagnosis,
    resetReport,
  };
};
