// _design/auth: validacion de escritura y RBAC a nivel de documento.
// Roles: db_admin (todo), tecnico (crea/edita lotes), productor (solo sus lotes), auditor (solo lectura).
function (newDoc, oldDoc, userCtx, secObj) {
  var roles = userCtx.roles || [];
  var isAdmin = roles.indexOf('db_admin') !== -1 || roles.indexOf('_admin') !== -1;
  if (isAdmin) { return; }
  if (roles.indexOf('auditor') !== -1 && roles.length === 1) {
    throw({forbidden: 'El rol auditor es de solo lectura.'});
  }
  if (newDoc._deleted) {
    throw({forbidden: 'Borrado fisico no permitido; use estado "anulado".'});
  }
  var req = ['type', 'lote_id', 'cooperativa_id', 'etapa', 'ts', 'owner'];
  for (var i = 0; i < req.length; i++) {
    if (newDoc[req[i]] === undefined) { throw({forbidden: 'Campo obligatorio: ' + req[i]}); }
  }
  var etapas = ['recoleccion', 'beneficio', 'secado', 'almacen', 'despacho'];
  if (etapas.indexOf(newDoc.etapa) === -1) { throw({forbidden: 'Etapa invalida.'}); }
  if (roles.indexOf('productor') !== -1 && roles.indexOf('tecnico') === -1 &&
      newDoc.owner !== userCtx.name) {
    throw({forbidden: 'Un productor solo escribe documentos propios.'});
  }
  // Un tecnico con rol coop-<id> solo puede escribir en su cooperativa.
  var coopsPermitidas = [];
  for (var j = 0; j < roles.length; j++) {
    if (roles[j].indexOf('coop-') === 0) { coopsPermitidas.push(roles[j].substring(5)); }
  }
  if (roles.indexOf('tecnico') !== -1 && coopsPermitidas.length > 0 &&
      coopsPermitidas.indexOf(newDoc.cooperativa_id) === -1) {
    throw({forbidden: 'El evento pertenece a otra cooperativa.'});
  }
  if (oldDoc && oldDoc.owner !== newDoc.owner) {
    throw({forbidden: 'El campo owner es inmutable.'});
  }
}
