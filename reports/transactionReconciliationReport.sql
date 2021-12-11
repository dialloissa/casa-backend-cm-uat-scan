SELECT DISTINCT
  qt.quoteId AS quoteId,
  payerPart.name AS senderDFSPId,
  payerPart.name AS senderDFSPName,
  payeeQp.fspId AS receiverDFSPId,
  payeePart.name AS receiverDFSPName,
  tfr.transferId AS hubTxnID,
  IF(txnSce.name = 'TRANSFER', 'P2P', (IF(txnSce.name = 'TRANSFER', 'MP', NULL))) AS transactionType,
  IF(qt.transactionRequestId IS NULL, 'Original', 'Reversal') AS natureOfTxnType,
  qt.createdDate AS requestDate,
  tfr.createdDate AS createdDate,
  IF(ssc.settlementStateId = 'SETTLED', ssc.createdDate, Cast(NULL as datetime)) AS settlementDate,
  payerQp.currencyId AS senderCountryCurrencyCode,
  payeeQp.currencyId AS receiverCountryCurrencyCode,
  payerQp.partyIdentifierValue AS senderId,
  payeeQp.partyIdentifierValue AS receiverId,
  tfr.amount AS reconciliationAmount,
  IF((payeeParty.firstName <> NULL && payeeParty.lastName <> NULL), 'RNR', 'RNND') AS receiverNameStatus,
  '' AS pricingOption,
  '' AS receiverKYCLevelStatus,
  ts.transferStateId AS status,
  ts.createdDate as modificationDate, '' AS errorCode,
  tfr.transferId AS senderDFSPTxnID,
  tfr.transferId AS receiverDFSPTxnID,
  IF(xfrFul.settlementWindowId IS NULL, '', Cast(xfrFul.settlementWindowId as char)) AS settlementWindowId,
  ssc.settlementStateId AS settlementState,
  ssc.createdDate AS settlementStateChangeDate
FROM
  quote qt
INNER JOIN
  transactionReference txnref
  ON qt.quoteId = txnref.quoteId
INNER JOIN
  transactionScenario txnSce
  ON qt.transactionScenarioId = txnSce.transactionScenarioId
INNER JOIN
  quoteParty payerQp
  ON qt.quoteId = payerQp.quoteId AND payerQp.partyTypeId = '1'
INNER JOIN
  quoteParty payeeQp
  ON qt.quoteId = payeeQp.quoteId AND payeeQp.partyTypeId = '2'
INNER JOIN
  participant payerPart
  ON payerQp.participantId = payerPart.participantId
INNER JOIN
  participant payeePart
  ON payeeQp.participantId = payeePart.participantId
INNER JOIN
  quoteResponse qr
  ON qr.quoteId = qt.quoteId
INNER JOIN
  transfer tfr
  ON tfr.transferId = txnref.transactionReferenceId
LEFT JOIN
  transferFulfilment xfrFul
  ON xfrFul.transferId = tfr.transferId
LEFT JOIN
  party payerParty
  ON payerQp.partyTypeId = payerParty.partyId
LEFT JOIN
  party payeeParty
  ON payerQp.partyTypeId = payeeParty.partyId
LEFT JOIN
  settlementSettlementWindow ssw
  ON ssw.settlementWindowId = xfrFul.settlementWindowId
LEFT JOIN
  settlement sett
  ON sett.settlementId = ssw.settlementId
LEFT JOIN
  settlementStateChange ssc
  ON ssc.settlementStateChangeId = sett.currentStateChangeId
LEFT JOIN
  (
      SELECT tsc.transferId, tsc.transferStateId, tsc.createdDate
      FROM
          transferStateChange tsc
      INNER JOIN
          (
              SELECT
                  MAX(tsc.transferStateChangeId) AS transferStateChangeId,
                  tsc.transferId
              FROM
                  transferStateChange tsc
              GROUP BY transferId
          ) mtsc
          ON mtsc.transferId = tsc.transferId AND tsc.transferStateChangeId = mtsc.transferStateChangeID
  ) ts
  ON ts.transferId = tfr.transferId
WHERE
  (payerPart.name = $P{FSP_ID} OR payeePart.name = $P{FSP_ID})
AND
  (xfrFul.settlementWindowId = $O{SETTLEMENT_WINDOW_ID} OR $O{SETTLEMENT_WINDOW_ID} IS NULL)
AND
  qt.createdDate BETWEEN STR_TO_DATE($P{START_DATE_TIME}, '%Y-%m-%dT%T') AND STR_TO_DATE($P{END_DATE_TIME}, '%Y-%m-%dT%T')
