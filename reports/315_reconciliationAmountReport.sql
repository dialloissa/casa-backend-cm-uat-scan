SELECT
  fromName,
  fromId,
  toName,
  toId,
  currency,
  numTransactions,
  TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM sent)) AS sent,
  TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM received)) AS received,
  TRIM(TRAILING '.' FROM TRIM(TRAILING '0' FROM net)) AS net,
  settlementWindowOpen,
  settlementWindowClose
FROM (
  SELECT
    payer.name AS fromName,
    payer.participantId AS fromId,
    payee.name AS toName,
    payee.participantId AS toId,
    pcPayer.currencyId AS currency,
    COUNT(txpPayer.transferId) AS numTransactions,
    CASE WHEN payer.participantId = $P{participantId} THEN sum(txpPayer.amount) ELSE 0 END AS sent,
    CASE WHEN payer.participantId = $P{participantId} THEN 0 ELSE sum(txpPayer.amount) END AS received,
    CASE WHEN payer.participantId = $P{participantId} THEN -sum(txpPayer.amount) ELSE sum(txpPayer.amount) END AS net,
    swOpen.createdDate AS settlementWindowOpen,
    swClose.createdDate AS settlementWindowClose
  FROM
    transferParticipant txpPayer
  INNER JOIN
    transferParticipant txpPayee
    ON txpPayer.transferId = txpPayee.transferId
    AND txpPayer.transferParticipantId != txpPayee.transferParticipantId
  INNER JOIN
    transferFulfilment txf
    ON txf.transferId = txpPayer.transferId
  INNER JOIN
    transferParticipantRoleType txprt
    ON txprt.transferParticipantRoleTypeId = txpPayer.transferParticipantRoleTypeId
    AND txprt.name = 'PAYER_DFSP'
  INNER JOIN
    participantCurrency pcPayer
    ON pcPayer.participantCurrencyId = txpPayer.participantCurrencyId
  INNER JOIN
    participantCurrency pcPayee
    ON pcPayee.participantCurrencyId = txpPayee.participantCurrencyId
  INNER JOIN
    participant payer
    ON pcPayer.participantId = payer.participantId
  INNER JOIN
    participant payee
    ON pcPayee.participantId = payee.participantId
  INNER JOIN
    settlementWindow sw
    ON sw.settlementWindowId = txf.settlementWindowId
  INNER JOIN
    settlementWindowStateChange swOpen
    ON swOpen.settlementWindowId = sw.settlementWindowId
  INNER JOIN
    settlementWindowStateChange swClose
    ON swClose.settlementWindowId = sw.settlementWindowId
  WHERE
    sw.settlementWindowId = $P{settlementWindowId}
    AND swOpen.settlementWindowStateId = 'OPEN'
    AND swClose.settlementWindowStateId = 'CLOSED'
    AND (payer.participantId = $P{participantId} OR payee.participantId = $P{participantId})
  GROUP BY
    payer.participantId,
    payee.participantId,
    currency,
    swOpen.createdDate,
    swClose.createdDate
) AS result
