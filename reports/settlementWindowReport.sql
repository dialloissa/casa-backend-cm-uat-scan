SELECT sq.*, swOpen.createdDate AS windowOpen, swClose.createdDate as windowClose
FROM
  (
      SELECT
          qp.fspId,
          sw.settlementWindowId,
          swsc.settlementWindowStateId AS state,
          COUNT(qp.amount) AS numTransactions,
          SUM(qp.amount) AS netPosition
      FROM
          central_ledger.settlementWindow AS sw
      LEFT JOIN
           central_ledger.transferFulfilment AS tf
           ON tf.settlementWindowId = sw.settlementWindowId
      LEFT JOIN
           central_ledger.transactionReference AS tr
           ON tf.transferId = tr.transactionReferenceId
      INNER JOIN
           central_ledger.transferParticipant AS tp
           ON tp.transferId = tf.transferId
      INNER JOIN
           central_ledger.transferParticipantRoleType AS trpt
           ON trpt.transferParticipantRoleTypeId = tp.transferParticipantRoleTypeId
      INNER JOIN
           central_ledger.settlementWindowStateChange AS swsc
           ON swsc.settlementWindowStateChangeId = sw.currentStateChangeId
      LEFT JOIN
           central_ledger.quoteParty AS qp
           ON qp.quoteId = tr.quoteId AND qp.transferParticipantRoleTypeId = tp.transferParticipantRoleTypeId
      GROUP BY qp.fspId, sw.settlementWindowId
  ) AS sq
INNER JOIN
  central_ledger.settlementWindowStateChange AS swOpen
  ON swOpen.settlementWindowId = sq.settlementWindowId
LEFT OUTER JOIN
  central_ledger.settlementWindowStateChange AS swClose
  ON swClose.settlementWindowId = sq.settlementWindowId AND swClose.settlementWindowStateId = 'CLOSED'
WHERE
swOpen.settlementWindowStateId = 'OPEN'
